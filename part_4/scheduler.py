import psutil
import scheduler_logger
import docker
import time
import sys
import os

client = docker.from_env()
Job = scheduler_logger.Job

# returns an array of cpu usage in percent, where the index i is the core i
def get_cpu_usage():
    return psutil.cpu_percent(interval=1, percpu=True)

configs = {
    Job.BLACKSCHOLES: {"image": "anakli/cca:parsec_blackscholes", "threads": 1},
    Job.CANNEAL: {"image": "anakli/cca:parsec_canneal", "threads": 4},
    Job.DEDUP: {"image": "anakli/cca:parsec_dedup", "threads": 4},
    Job.FERRET: {"image": "anakli/cca:parsec_ferret", "threads": 8},
    Job.FREQMINE: {"image": "anakli/cca:parsec_freqmine", "threads": 8},
    Job.VIPS: {"image": "anakli/cca:parsec_vips", "threads": 4},
    Job.RADIX: {"image": "anakli/cca:splash2x_radix", "threads": 2}
}

def check_SLO(pid_of_memcached, logger, memecached_on_cpu1):
    current_cpu_usage = get_cpu_usage()

    if (not memecached_on_cpu1) and (current_cpu_usage[0] >= 55):
        # if needed, stop job at cpu 1
        # todo

        # shedule memechached on cpu 1 as well
        os.system(f"sudo taskset -a -cp 0-1 {pid_of_memcached}")
        logger.update_cores(Job.MEMCACHED, [0, 1])

        memecached_on_cpu1 = True
        time.sleep(3) 

    elif (memecached_on_cpu1) and (current_cpu_usage[1] <= 30):
        # shedule memechached on cpu 0 only
        os.system(f"sudo taskset -a -cp 0 {pid_of_memcached}")
        logger.update_cores(Job.MEMCACHED, [0])
        
        # resume jop that is still on cpu 1
        # todo

        memecached_on_cpu1 = False

    return memecached_on_cpu1


def main():
    logger = scheduler_logger.SchedulerLogger()

    if len(sys.argv) != 2:
        print("Usage: python3 scheduler.py to many arguments")
        return
    
    # need the pid of memcached to schedule it on different cores
    pid_of_memcached = sys.argv[1]
    memecached_on_cpu1 = False # python does not know global variables...

    '''
    for j in Job:
        # We dont want to execute the scheduler task nor memcached
        if j == Job.SCHEDULER or j== Job.MEMCACHED:
            continue

        settings = configs[j]
        image = settings["image"]
        threads = settings["threads"]

        logger.job_start(j,[],0)
        print(j)
        print(j.value)
        container = client.containers.run(
            image= image,
            command= ["./run", "-a", "run", "-S", "parsec", "-p", j.value, "-i", "native", "-n", str(threads)],
            cpuset_cpus= '2',
            detach= True,
            remove= False,
            name= j.value
        )
        
        container.wait()

        # while True:
        #     if(container.status != "running"):
        #         break
        #     container.reload()

        logger.job_end(j)
        print(container.logs())
        '''
    
    while True:
        memecached_on_cpu1 = check_SLO(pid_of_memcached, logger, memecached_on_cpu1)
        print(get_cpu_usage())

    logger.end()

if __name__ == "__main__":
    main()
