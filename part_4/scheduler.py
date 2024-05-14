# TODO be able to run a container job
# TODO Measure CPU Usage
# TODO shedule policy based on CPU Usage
import scheduler_logger 
from enum import Enum
import docker

logger = scheduler_logger.SchedulerLogger
jobs = scheduler_logger.Job

client = docker.from_env()

job_settings = {
    jobs.BLACKSCHOLES: {"image": "anakli/cca:parsec_blackscholes", "threads": 1},
    jobs.CANNEAL: {"image": "anakli/cca:parsec_canneal", "threads": 4},
    jobs.DEDUP: {"image": "anakli/cca:parsec_dedup", "threads": 4},
    jobs.FERRET: {"image": "anakli/cca:parsec_ferret", "threads": 8},
    jobs.FREQMINE: {"image": "anakli/cca:parsec_freqmine", "threads": 8},
    jobs.VIPS: {"image": "anakli/cca:parsec_vips", "threads": 4},
    jobs.RADIX: {"image": "anakli/cca:splash2x_radix", "threads": 2}
}

def main():
    logger = scheduler_logger.SchedulerLogger

    for j in jobs:
        logger.job_start(j)
        logger.job_end(j)
        container = client.containers.run(j["image"], f"./run -a run -S parsec -p {j.value} -i native -n {num_threads}", cpuset_cpus=",".join(map(str, [0])), detach=True)
    print("work in progress")
    

if __name__ == "__main__":
    main()
