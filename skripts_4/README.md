### Part 4

### cluster_setpu_script
- setus up the cluster and installs everything on the respective machine
- nothing will be running, as the server first needs to preload images before we can run the measurments
- because of the relative paths, it needs to be executed from /cloud-comp-arch-project/ with "./skripts_4/cluster_setup_script.sh"

### preloader
- needs to be copied onto the memcache server and be run to preload all the doker images
- ssh into the server for this

### sheduler
- actual sheduler, also copied onto the memcache server
- run it, after client-agent and client-measure are running
- note that sheduler_logger.py has functions needed for 4.3 and 4.4