import psutil
import scheduler_logger 
import docker

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

def main():
    logger = scheduler_logger.SchedulerLogger()

    for j in Job:
        # We dont want to execute the scheduler task
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
        

if __name__ == "__main__":
    main()
