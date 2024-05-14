import psutil

# returns an array of cpu usage in percent, where the index i is the core i
def get_cpu_usage():
    return psutil.cpu_percent(interval=1, percpu=True)

def main():
    print(get_cpu_usage())

if __name__ == "__main__":
    main()
