import psutil
import scheduler_logger
import docker
import time
import sys
import os

client = docker.from_env()
Job = scheduler_logger.Job

configs = {
    Job.BLACKSCHOLES: {"image": "anakli/cca:parsec_blackscholes", "threads": 1, "cores": [1]},
    Job.CANNEAL: {"image": "anakli/cca:parsec_canneal", "threads": 4, "cores": [2,3]},
    Job.DEDUP: {"image": "anakli/cca:parsec_dedup", "threads": 4, "cores": [1]},
    Job.FERRET: {"image": "anakli/cca:parsec_ferret", "threads": 8, "cores": [2,3]},
    Job.FREQMINE: {"image": "anakli/cca:parsec_freqmine", "threads": 8, "cores": [2,3]},
    Job.VIPS: {"image": "anakli/cca:parsec_vips", "threads": 4, "cores": [1]},
    Job.RADIX: {"image": "anakli/cca:splash2x_radix", "threads": 2, "cores": [1]}
}

# transforms list of cpus [x,y,z] to cpuset of the form "x-z"
def to_cpuset(cpus):
    cpus.sort()
    return str(cpus[0]) + "-" + str(cpus[-1])

class RunningJob:
    def __init__(self,logger,job):
        self.container = None
        self.job = job
        self.name = job.value
        self.logger = logger
        self.cores = configs[job]["cores"]
        self.image = configs[job]["image"]
        self.threads = configs[job]["threads"]

    def start(self):
        self.logger.job_start(self.job, self.cores, self.threads)
        if self.name == "radix":
                self.container = client.containers.run(
                image= self.image,
                command= ["./run", "-a", "run", "-S", "splash2x", "-p", self.name, "-i", "native", "-n", str(self.threads)],
                cpuset_cpus= to_cpuset(self.cores),
                detach= True,
                remove= False,
                name= self.job.value
            )
        else:
            self.container = client.containers.run(
                image= self.image,
                command= ["./run", "-a", "run", "-S", "parsec", "-p", self.name, "-i", "native", "-n", str(self.threads)],
                cpuset_cpus= to_cpuset(self.cores),
                detach= True,
                remove= False,
                name= self.name
            )

    # new_core_Set has to be a string "0-3" or "2"
    # new_core_list is a list of the cores, lke [2, 3] or [0]
    def update_cores(self, new_cores):
        self.logger.update_cores(self.job, new_cores)
        self.container.update(cpuset_cpus=to_cpuset(new_cores))
    
    def stop(self):
        if self.container != None and self.container.status == "running":
            self.logger.job_pause(self.job)
            self.container.pause()

    def resume(self):
        self.logger.job_unpause(self.job)
        self.container.unpause()

    def is_finished(self):
        self.container.reload()
        if(self.container.status == "exited"):
            self.logger.job_end(self.job)
            self.logger.custom_event(self.job, "container exit status: " + str(self.container.wait()['StatusCode']))
            self.container.remove()
            self.container = None
            self.job = None
            return 1
        else:
            return 0 

# returns an array of cpu usage in percent, where the index i is the core i
def get_cpu_usage():
    return psutil.cpu_percent(interval=1, percpu=True)

# this function takes care of scheudling all jobs for core 1 as well as memcached
def check_SLO(pid_of_memcached, logger, memecached_on_cpu1, concurrent_jobs):
    current_cpu_usage = get_cpu_usage()

    if (not memecached_on_cpu1) and (current_cpu_usage[0] >= 55):
        # shedule memechached on cpu 1 as well
        os.system(f"sudo taskset -a -cp 0-1 {pid_of_memcached}")
        logger.update_cores(Job.MEMCACHED, [0, 1])

        # if needed, stop job at cpu 1
        for j in concurrent_jobs:
            j.pause()
        
        memecached_on_cpu1 = True
        time.sleep(3) 

    elif (memecached_on_cpu1) and (current_cpu_usage[1] <= 30):
        # shedule memechached on cpu 0 only
        os.system(f"sudo taskset -a -cp 0 {pid_of_memcached}")
        logger.update_cores(Job.MEMCACHED, [0])
        
        # resume jop that is still on cpu 1 
        for j in concurrent_jobs:
            j.resume()
            
        memecached_on_cpu1 = False
        time.sleep(1) # code will crash without this

    return memecached_on_cpu1


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 scheduler.py to many arguments")
        return
    
    # need the pid of memcached to schedule it on different cores
    # python does not know global variables, hence, here they are
    logger = scheduler_logger.SchedulerLogger()
    pid_of_memcached = sys.argv[1]
    memecached_on_cpu1 = False 
    os.system(f"sudo taskset -a -cp 0 {pid_of_memcached}")
    logger.job_start(Job.MEMCACHED, [0], 2)

    running_0 = [] # core is fully reserved for memcached
    running_1 = [] # core where memcached has priority
    running_2 = [] # jobs core
    running_3 = [] # jobs core

    jobs_1 = [Job.RADIX, Job.VIPS, Job.DEDUP, Job.BLACKSCHOLES] 
    jobs_23 = [Job.FERRET, Job.FREQMINE, Job.CANNEAL] 

    while len(running + jobs_1 + jobs_23) > 0:
        cpu_usage = get_cpu_usage()
        core_0 = cpu_usage[0] # core is fully reserved for memcached
        core_1 = cpu_usage[1] # core where memcached has priority
        core_2 = cpu_usage[2] # jobs core
        core_3 = cpu_usage[3] # jobs core

        if(core_1 and (not memecached_on_cpu1)):
            new_job = RunningJob(logger, jobs_1.pop())
            new_job.start()
            core_1.push(core_1)
            
        if(core_2 < 50 or core_3 < 50):
            new_job = RunningJob(logger, jobs_23.pop())
            new_job.start()
            core_1.push(core_1)

        # check if running jobs have exited
        running_0.filter(lambda j: (not j.is_finished()))
        running_1.filter(lambda j: (not j.is_finished()))
        running_2.filter(lambda j: (not j.is_finished()))
        running_3.filter(lambda j: (not j.is_finished()))
        running = running_0 + running_1 + running_2 + running_3

        print("running on core0: " + str(running_0))
        print("running on core1: " + str(running_1))
        print("running on core2: " + str(running_2))
        print("running on core3: " + str(running_3))

        # check SLO
        memecached_on_cpu1 = check_SLO(pid_of_memcached, logger, memecached_on_cpu1, running_1)
        
    logger.end()
    print("done")

if __name__ == "__main__":
    main()
