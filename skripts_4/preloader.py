from enum import Enum
import docker

client = docker.from_env()

class Job(Enum):
    BLACKSCHOLES = "blackscholes"
    CANNEAL = "canneal"
    DEDUP = "dedup"
    FERRET = "ferret"
    FREQMINE = "freqmine"
    RADIX = "radix"
    VIPS = "vips"

job_settings = {
    Job.BLACKSCHOLES: {"image": "anakli/cca:parsec_blackscholes", "threads": 1},
    Job.CANNEAL: {"image": "anakli/cca:parsec_canneal", "threads": 4},
    Job.DEDUP: {"image": "anakli/cca:parsec_dedup", "threads": 4},
    Job.FERRET: {"image": "anakli/cca:parsec_ferret", "threads": 8},
    Job.FREQMINE: {"image": "anakli/cca:parsec_freqmine", "threads": 8},
    Job.VIPS: {"image": "anakli/cca:parsec_vips", "threads": 4},
    Job.RADIX: {"image": "anakli/cca:splash2x_radix", "threads": 2}
}

def preload_container(job):
    settings = job_settings[job]
    image = settings["image"]
    num_threads = settings["threads"]

    try:
        print("pulling image: " + image)
        container = client.containers.run(image, f"./run -a run -S parsec -p {job.value} -i native -n {num_threads}", cpuset_cpus=",".join(map(str, [0])), detach=True)
        container.stop()
        print("finished pulling image: " + image)
    except docker.errors.APIError as e:
        print(f"Error running container for {job.value}: {e}")

def main():
    for job in Job:
        preload_container(job) 

if __name__ == "__main__":
    main()