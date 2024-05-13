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

## Execute Client Agent
Open a new terminal and execute
```
sh 1_client_agent.sh
```
## Execute Client Measure
Open a new terminal and execute
```
sh 2_client_measure.sh
```

## Execute Scheduler
Open a new terminal and execute (after you started client-agent and client-measure)
```
sh 3_scheduler.sh
```
Please note that ``sheduler_logger.py`` has functions needed for tasks 4.3 and 4.4.
