import psutil
import scheduler_logger
import docker
import time
import sys
import os

client = docker.from_env()
Job = scheduler_logger.Job

configs = {
    Job.BLACKSCHOLES: {"image": "anakli/cca:parsec_blackscholes", "threads": 1, "cpuset_cpus": '1'},
    Job.CANNEAL: {"image": "anakli/cca:parsec_canneal", "threads": 4, "cpuset_cpus": '2-3'},
    Job.DEDUP: {"image": "anakli/cca:parsec_dedup", "threads": 4, "cpuset_cpus": '1'},
    Job.FERRET: {"image": "anakli/cca:parsec_ferret", "threads": 8, "cpuset_cpus": '2-3'},
    Job.FREQMINE: {"image": "anakli/cca:parsec_freqmine", "threads": 8, "cpuset_cpus": '2-3'},
    Job.VIPS: {"image": "anakli/cca:parsec_vips", "threads": 4, "cpuset_cpus": '1'},
    Job.RADIX: {"image": "anakli/cca:splash2x_radix", "threads": 2, "cpuset_cpus": '1'}
}

class CPU_Core:
    def __init__(self, index):
        self.index = index
        self.container = None
        self.job = None

    def start_job(self, job, core_list, logger):
        self.job = job
        settings = configs[job]
        image = settings["image"]
        threads = settings["threads"]
        cores = settings["cpuset_cpus"]

        logger.job_start(job, core_list, threads)
        if job.value == "radix":
                self.container = client.containers.run(
                image= image,
                command= ["./run", "-a", "run", "-S", "splash2x", "-p", job.value, "-i", "native", "-n", str(threads)],
                cpuset_cpus= cores,
                detach= True,
                remove= False,
                name= job.value
            )
        else:
            self.container = client.containers.run(
                image= image,
                command= ["./run", "-a", "run", "-S", "parsec", "-p", job.value, "-i", "native", "-n", str(threads)],
                cpuset_cpus= cores,
                detach= True,
                remove= False,
                name= job.value
            )

    # new_core_Set has to be a string "0-3" or "2"
    # new_core_list is a list of the cores, lke [2, 3] or [0]
    def update_cores(self, logger, new_core_list, new_core_Set):
        logger.update_cores(self.job, new_core_list)
        self.container.update(cpuset_cpus=new_core_Set)
    
    def stop_task(self, logger):
        if self.container != None and self.container.status == "running":
            logger.job_pause(self.job)
            self.container.pause()

    def resume_task(self, logger):
        logger.job_unpause(self.job)
        self.container.unpause()

    def check_container(self, logger):
        self.container.reload()
        if(self.container.status == "exited"):
            logger.job_end(self.job)
            logger.custom_event(self.job, "container exit status: " + str(self.container.wait()['StatusCode']))
            self.container.remove()
            self.container = None
            self.job = None
            return 1
        else:
            return 0 

# returns an array of cpu usage in percent, where the index i is the core i
def get_cpu_usage():
    return psutil.cpu_percent(interval=1, percpu=True)

# this function takes care of scheudling all jobs for core as well as memcached
def check_SLO(pid_of_memcached, logger, memecached_on_cpu1, core_1):
    current_cpu_usage = get_cpu_usage()

    if (not memecached_on_cpu1) and (current_cpu_usage[0] >= 55):
        # shedule memechached on cpu 1 as well
        os.system(f"sudo taskset -a -cp 0-1 {pid_of_memcached}")
        logger.update_cores(Job.MEMCACHED, [0, 1])

        # if needed, stop job at cpu 1
        if core_1.job != None:
            core_1.stop_task(logger)
        
        memecached_on_cpu1 = True
        time.sleep(3) 

    elif (memecached_on_cpu1) and (current_cpu_usage[1] <= 30):
        # shedule memechached on cpu 0 only
        os.system(f"sudo taskset -a -cp 0 {pid_of_memcached}")
        logger.update_cores(Job.MEMCACHED, [0])
        
        # resume jop that is still on cpu 1 
        if core_1.job != None:
            core_1.resume_task(logger)
            
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

    number_of_finished_jobs = 0
    cores = []
    for i in range(4):
        cores.append(CPU_Core(i))

    job_1 = [Job.RADIX, Job.VIPS, Job.DEDUP, Job.BLACKSCHOLES] 
    job_2 = [Job.FERRET, Job.FREQMINE, Job.CANNEAL] 

    while number_of_finished_jobs < 7:
        # check, if something is running on core 1, if not, schedule job on core 1, if memechached is not running there
        if (cores[1].job == None) and job_1 and (not memecached_on_cpu1):
            temp_j = job_1.pop()
            print(temp_j)
            cores[1].start_job(temp_j, [1], logger)

        # check, if something is running on core 2, if not, schedule job on core 2 and 3
        if cores[2].job == None and job_2:
            temp_j = job_2.pop()
            print(temp_j)
            cores[2].start_job(temp_j, [2, 3], logger)

        # needs now smarter scheduling
        # we can also change cores of jobs, see function in CPU_Core
        # right now, we only schedule some jobs on core 1 or on cores (2 and 3) toghether
        # we never check, if core 2 and 3 are empty, to schedule the jobs on core 1 to either other core
        # the cores are currently hardcoded in the configuration list, see at the very top on the code

        # check, if job is finished on core 1 or 2
        if cores[1].job != None:
            number_of_finished_jobs = number_of_finished_jobs + cores[1].check_container(logger)
        if cores[2].job != None:    
            number_of_finished_jobs = number_of_finished_jobs + cores[2].check_container(logger)

        # check SLO
        memecached_on_cpu1 = check_SLO(pid_of_memcached, logger, memecached_on_cpu1,  cores[1])
        
    logger.end()
    print("done")

if __name__ == "__main__":
    main()
