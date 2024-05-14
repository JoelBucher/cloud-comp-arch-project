# Task 4
## Setup Cluster
Make sure to run the following setup code in your active terminal
```
gcloud auth login
gcloud auth application-default login
```

When the cluster is being created all configuration flags
```
create_cluster=true
install_mcperf=true
interactive_mode=true
```
should be set to ``true``. If this is the case you can execute the setup script
```
sh 0_setup.sh
```

## Execute Client Agent (working)
Open a new terminal and execute
```
sh 1_client_agent.sh
```
## Execute Client Measure (working)
Open a new terminal and execute
```
sh 2_client_measure.sh
```

## Execute Scheduler
Open a new terminal and execute (after you started client-agent and client-measure)
```
sh 3_scheduler.sh
```
After executing the scheduler script, please execute the remote scheduler script using
```
sh 4_scheduler_remote.sh
```
on the remote VM that has been opened by the former script. If the remote script should be unresponsive or not execute any python files, please perform the following steps:
```
python3 preloader.py
python3 scheduler.py <pid_of_memcached>
```
