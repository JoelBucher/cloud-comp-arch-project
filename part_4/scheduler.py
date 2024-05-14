import psutil
import scheduler_logger 
from enum import Enum
import docker

logger = scheduler_logger.SchedulerLogger
jobs = scheduler_logger.Job

client = docker.from_env()

# returns an array of cpu usage in percent, where the index i is the core i
def get_cpu_usage():
    return psutil.cpu_percent(interval=1, percpu=True)

configs = {
    jobs.BLACKSCHOLES: {"name": "blackscholes", "image": "anakli/cca:parsec_blackscholes", "threads": 1},
    jobs.CANNEAL: {"name": "canneal", "image": "anakli/cca:parsec_canneal", "threads": 4},
    jobs.DEDUP: {"name": "dedup", "image": "anakli/cca:parsec_dedup", "threads": 4},
    jobs.FERRET: {"name": "ferret", "image": "anakli/cca:parsec_ferret", "threads": 8},
    jobs.FREQMINE: {"name": "freqmine", "image": "anakli/cca:parsec_freqmine", "threads": 8},
    jobs.VIPS: {"name": "vips", "image": "anakli/cca:parsec_vips", "threads": 4},
    jobs.RADIX: {"name": "radix", "image": "anakli/cca:splash2x_radix", "threads": 2}
}

def create_container(job):
    return {
    'image': job["image"],
    'command': "./run -a run -S parsec -p %s -i native -n %s" % (job['name'],job['threads']),
    'cpuset_cpus': '0',
    'detach': True,
    'remove': True,
    'name': 'parsec'
}

def main():
    logger = scheduler_logger.SchedulerLogger

    for c in configs:
        name = c["name"]
        logger.job_start(name)
        container = client.containers.run(**create_container(c))
        container.wait()
        logger.job_end(name)
        get_cpu_usage()

if __name__ == "__main__":
    main()
