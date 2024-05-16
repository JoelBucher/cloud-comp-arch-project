import psutil
import scheduler_logger
import docker
import time
import sys
import os
import pgrep

client = docker.from_env()
Job = scheduler_logger.Job

configs = {
    Job.BLACKSCHOLES:   {"threads": 1, "priority": [1],     "image": "anakli/cca:parsec_blackscholes"},
    Job.CANNEAL:        {"threads": 4, "priority": [2,3],   "image": "anakli/cca:parsec_canneal"},
    Job.DEDUP:          {"threads": 4, "priority": [1],     "image": "anakli/cca:parsec_dedup"},
    Job.FERRET:         {"threads": 8, "priority": [2,3],   "image": "anakli/cca:parsec_ferret"},
    Job.FREQMINE:       {"threads": 8, "priority": [2,3],   "image": "anakli/cca:parsec_freqmine"},
    Job.VIPS:           {"threads": 4, "priority": [1],     "image": "anakli/cca:parsec_vips"},
    Job.RADIX:          {"threads": 2, "priority": [1],     "image": "anakli/cca:splash2x_radix"}
}

def get_job(jobs, core):
    priority_jobs = list(filter(lambda j: core in configs[j]["priority"], jobs))

    if(len(priority_jobs) > 0):
        return priority_jobs[0] 
    else:
        return jobs[0]


class RunningJob:
    def __init__(self,logger,job,core):
        self.container = None
        self.job = job
        self.name = job.value
        self.logger = logger
        self.cores = str(core)
        self.image = configs[job]["image"]
        self.threads = configs[job]["threads"]
    
    def toString(self):
        self.container.reload()
        return "[%s] %s (%s)" % (self.container.status, self.name, self.cores)

    def start(self):
        self.logger.job_start(self.job, self.cores, self.threads)
        if self.name == "radix":
                self.container = client.containers.run(
                image= self.image,
                command= ["./run", "-a", "run", "-S", "splash2x", "-p", self.name, "-i", "native", "-n", str(self.threads)],
                cpuset_cpus= self.cores,
                detach= True,
                remove= False,
                name= self.job.value
            )
        else:
            self.container = client.containers.run(
                image= self.image,
                command= ["./run", "-a", "run", "-S", "parsec", "-p", self.name, "-i", "native", "-n", str(self.threads)],
                cpuset_cpus= self.cores,
                detach= True,
                remove= False,
                name= self.name
            )

    # new_core_Set has to be a string "0-3" or "2"
    def update_cores(self, new_cores):
        self.logger.update_cores(self.job,new_cores)
        self.cpuset_cpus = new_cores 
        self.container.update(cpuset_cpus=new_cores)
    
    def pause(self):
        self.container.reload()
        if self.container != None and self.container.status == "running":
            self.logger.job_pause(self.job)
            self.container.pause()

    def resume(self):
        self.container.reload()
        if self.container != None and ((self.container.status == "paused")) :
            self.logger.job_unpause(self.job)
            self.container.unpause()

    def is_finished(self):
        if(self.container.status != "exited"):
            self.container.reload()
            
        if(self.container.status == "exited"):
            self.logger.job_end(self.job)
            self.logger.custom_event(self.job, "container exit status: " + str(self.container.wait()['StatusCode']))
            self.container.remove()
            return 1
        else:
            return 0 

# returns an array of cpu usage in percent, where the index i is the core i
def get_cpu_usage():
    return psutil.cpu_percent(interval=1, percpu=True)

# this function takes care of scheudling all jobs for core 1 as well as memcached
def check_SLO(pid_of_memcached, logger, memecached_on_cpu1, concurrent_jobs):
    current_cpu_usage = get_cpu_usage()

    if (not memecached_on_cpu1) and (current_cpu_usage[0] >= 70):
        # shedule memechached on cpu 1 as well
        os.system(f"sudo taskset -a -cp 0-1 {pid_of_memcached}")
        logger.update_cores(Job.MEMCACHED, "0-1")

        # if needed, stop job at cpu 1
        for j in concurrent_jobs:
            j.pause()
        
        memecached_on_cpu1 = True
        time.sleep(3) 

    elif (memecached_on_cpu1) and (current_cpu_usage[1] <= 50):
        # shedule memechached on cpu 0 only
        os.system(f"sudo taskset -a -cp 0 {pid_of_memcached}")
        logger.update_cores(Job.MEMCACHED, "0")
        
        # resume jop that is still on cpu 1 
        for j in concurrent_jobs:
            j.resume()
            
        memecached_on_cpu1 = False
        time.sleep(1) # code will crash without this

    return memecached_on_cpu1

clean_cpu = True
def main():
    # need the pid of memcached to schedule it on different cores
    # python does not know global variables, hence, here they are
    logger = scheduler_logger.SchedulerLogger()

    pid_of_memcached = pgrep.pgrep("memcached")[0]
    print("memcached pid: ", pid_of_memcached)

    memecached_on_cpu1 = False 
    os.system(f"sudo taskset -a -cp 0 {pid_of_memcached}")
    logger.job_start(Job.MEMCACHED, [0], 2)

    running = []
    running_0 = [] # core is fully reserved for memcached
    running_1 = [] # core where memcached has priority
    running_2 = [] # jobs core
    running_3 = [] # jobs core

    jobs = [Job.RADIX, Job.VIPS, Job.BLACKSCHOLES, Job.DEDUP, Job.FERRET, Job.FREQMINE, Job.CANNEAL] 

    while len(running + jobs) > 0:
        cpu_usage = get_cpu_usage()
        clean_cpu1 = True
        clean_cpu2 = True
        clean_cpu3 = True

        core_0 = cpu_usage[0] # core is fully reserved for memcached
        core_1 = cpu_usage[1] # core where memcached has priority
        core_2 = cpu_usage[2] # jobs core
        core_3 = cpu_usage[3] # jobs core

        print("------")
        print("cpu: " + str(cpu_usage))
        
        if(core_1 and (not memecached_on_cpu1) and (len(jobs) > 0) and core_1 < 50):
            priority = get_job(jobs,1)
            new_job = RunningJob(logger, priority, 1)
            new_job.start()

            running_1.append(new_job)
            jobs.remove(priority)
            clean_cpu1 = False

        if(core_2 < 50 and (len(jobs) > 0)):
            priority = get_job(jobs,2)
            new_job = RunningJob(logger, priority, 2)
            new_job.start()

            running_2.append(new_job)
            jobs.remove(priority)
            clean_cpu2 = False
            
        if(core_3 < 50 and (len(jobs) > 0)):
            priority = get_job(jobs,3)
            new_job = RunningJob(logger, priority, 3)
            new_job.start()

            running_3.append(new_job)
            jobs.remove(priority)
            clean_cpu3 = False

        has_paused_tasks = (len(jobs) == 0) and (len(running_1) > 0) and memecached_on_cpu1
        if(clean_cpu2 and clean_cpu3 and has_paused_tasks and core_2 < 50 and core_3 < 50):
            j = running_1[0]
            j.update_cores("2-3")
            j.resume()
            running_1.remove(j)
            running_2.append(j)
            running_3.append(j)

        elif(clean_cpu2 and has_paused_tasks and core_2 < 50):
            j = running_1[0]
            j.update_cores("2")
            j.resume()
            running_1.remove(j)
            running_2.append(j)

        elif(clean_cpu3 and has_paused_tasks and core_3 < 50):
            j = running_1[0]
            j.update_cores("3")
            j.resume()
            running_1.remove(j)
            running_3.append(j)

        if(clean_cpu3 and (len(jobs) == 0) and (len(running_2) > 0) and (len(running_3) == 0)):
            j = running_2[0]
            j.update_cores("2-3")
            j.resume()
            running_3.append(j)
        
        if(clean_cpu2 and (len(jobs) == 0) and (len(running_3) > 0) and (len(running_2) == 0)):
            j = running_3[0]
            j.update_cores("2-3")
            j.resume()
            running_2.append(j)

        print("jobs left: " + str(jobs))

        # check if running jobs have exited
        running_0 = list(filter(lambda j: ((j is not None) and (not j.is_finished())), running_0))
        running_1 = list(filter(lambda j: ((j is not None) and (not j.is_finished())), running_1))
        running_2 = list(filter(lambda j: ((j is not None) and (not j.is_finished())), running_2))
        running_3 = list(filter(lambda j: ((j is not None) and (not j.is_finished())), running_3))
        running = running_0 + running_1 + running_2 + running_3

        print("running on core0: memcached")

        out1 = "running on core1: "
        if(memecached_on_cpu1):
            out1 += "memcached "
        for j in running_1:
            out1 += j.toString()
        print(out1)

        out2 = "running on core2: "
        for j in running_2:
            out2 += j.toString()
        print(out2)

        out3 = "running on core3: "
        for j in running_3:
            out3 += j.toString()
        print(out3)

        # check SLO
        memecached_on_cpu1 = check_SLO(pid_of_memcached, logger, memecached_on_cpu1, running_1)
        
        print("------")

    logger.end()
    print("done")

if __name__ == "__main__":
    main()
