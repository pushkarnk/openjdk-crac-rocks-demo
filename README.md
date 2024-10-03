## Checkpointing and restoring the SpringBoot PetClinic Application using OpenJDK CRaC

This tutorial is a hands-on introduction to [OpenJDK CRaC (Co-ordinated Restore at Checkpoint)](https://openjdk.org/projects/crac/). It uses the popular [SpringBoot PetClinic](https://github.com/spring-projects/spring-petclinic) sample application. OpenJDK CRaC packages for [v17](https://launchpad.net/ubuntu/+source/openjdk-17-crac) and [v21](https://launchpad.net/ubuntu/+source/openjdk-21-crac) are introduced in Ubuntu, in the Oracular Oriole release.

### Instructions
For the purpose of this tutorial, we use Ubuntu 24.04 (Noble Numbat). We will use the OpenJDK CRaC v17 package which is made available, for Ubuntu 24.04,  through [this PPA](https://launchpad.net/~pushkarnk/+archive/ubuntu/openjdk-crac-noble). SpringBoot added support for OpenJDK CRaC in version 3.2.0. We use a [modified PetClinic](https://github.com/pushkarnk/spring-petclinic) that [puts to use](https://github.com/pushkarnk/spring-petclinic/blob/main/pom.xml#L43) SpringBoot's CRaC capabilities.

We will try checkpointing and restoring in containers created from Ubuntu Rock images. Let us begin.

#### Step 1: Install rockcraft
We need [rockcraft](https://documentation.ubuntu.com/rockcraft/en/latest/) to build [Ubuntu Rock images](https://ubuntu.com/server/docs/about-rock-images).
```
sudo snap install rockcraft --classic
```

#### Step 2: Install docker
We use docker to run containers spawned from the Ubuntu rock images.
```
sudo snap install docker
```

#### Step 2: Clone this repository
```
git clone https://github.com/pushkarnk/openjdk-crac-rocks-demo
```
#### Step 3: Create the checkpointer rock
```
cd openjdk-crac-rocks-demo/checkpoint
rockcraft pack
```
This should take a few minutes to complete. The rockcraft build:
1. Installs openjdk-17-jdk-headless as a build-only package
2. Clones the modified version of spring-petclinic
3. Does a maven build of spring-petclinic using openjdk-17
4. Installs openjdk-17-crac-jdk-headless as an overlay (runtime) package.

At the end of the `rockcraft pack` command, the checkpointer rock named `spring-petclinic-checkpointer_0.0.1_amd64.rock` must be generated in the PWD. The rock is in the [OCI-archive format](https://specs.opencontainers.org/image-spec/).

#### Step 4: Copy the checkpointer rock as a Docker image to the docker-daemon
To be able to spawn a Docker container out of the checkpointer rock, we copy it as a Docker image to the [docker-daemon](https://docs.docker.com/engine/daemon/), using [skopeo](https://github.com/containers/skopeo).
```
sudo /snap/rockcraft/current/bin/skopeo --insecure-policy copy oci-archive:spring-petclinic-checkpointer_0.0.1_amd64.rock docker-daemon:spring-petclinic-checkpointer:0.0.1
```
The output should look like:
```
Getting image source signatures
Copying blob eda6120e237e done   | 
Copying blob 794c97974df7 done   | 
Copying blob 143560518a20 done   | 
Copying blob e98a261fb433 done   | 
Copying blob be93573b2c91 done   | 
Copying config 0bc2e4818b done   | 
Writing manifest to image destination
```

#### Step 5: Run SpringBoot PetClinic using the checkpointer Docker image
The checkpointer Rock has a service named [petclinic](https://github.com/pushkarnk/openjdk-crac-rocks-demo/blob/main/checkpoint/rockcraft.yaml#L21) which is to be started to launch the PetClinic application such that it could be [checkpointed](https://docs.azul.com/core/crac/crac-guidelines#generate-checkpoint).
```
 sudo docker run \
    -p 8080:8080 \
    --cap-add=CHECKPOINT_RESTORE --cap-add=SYS_PTRACE \
    -v $PWD/data:/var/lib/pebble/default/crac-files \
    --rm --name springboot-petclinic-checkpointer \
    spring-petclinic-checkpointer:0.0.1 \
    --args petclinic \; --verbose start petclinic
```
Here is the breakdown of the command:
 - _-p 8080:8080_: Requests received on host-port 8080 will be published to container-port 8080. This means the PetClinic service will be available to the host as well.
 - _--cap-add=CHECKPOINT_RESTORE --cap-add=SYS_PTRACE_: these capabilities are necessary for checkpointing to work in the Docker container
 - _-v $PWD/data:/var/lib/pebble/default/crac-files_: mount host-directory $PWD/data to the container location where the checkpoint data will be dumped by criu
 - _--rm_: delete the container after this command completes
 - _--name springboot-petclinic-checkpointer_: name of the resulting container
 - _spring-petclinic-checkpointer:0.0.1_: the Docker image that we want to use
 - _--args petclinic \; --verbose start petclinic_: these args are forwarded to the [Pebble](https://documentation.ubuntu.com/rockcraft/en/latest/explanation/pebble/) daemon that is run (by default) by rock images. In short, we are running the [petclinic service]([see here](https://github.com/pushkarnk/openjdk-crac-rocks-demo/blob/main/checkpoint/rockcraft.yaml#L21)) with _--verbose_ causing the service logs to be included in the pebble logs.

You must be able to see the PetClinic initialisation along with its ascii art. The PetClinic application should be up in 5-6 seconds.
```
Started PetClinicApplication in 5.204 seconds (process running for 5.577)
```
While 5-6s appears quick to the naked eye, it might be quite a significant delay in real-world, cloud-based services. 

You may now try accessing http://localhost:8080 in a browser!

#### Step 6: Checkpoint the SpringBoot PetClinic application
From another (secondary) terminal window, issue this command to checkpoint the PetClinic application:
```
sudo docker exec springboot-petclinic-checkpointer pebble start petclinic-checkpoint
```
This command might report an error. Please ignore.
```
error: cannot perform the following tasks:
- Start service "petclinic-checkpoint" (cannot start service: exited quickly with code 0)
```

We are triggering the checkpoint command through the Pebble service named [petclinic-checkpoint](https://github.com/pushkarnk/openjdk-crac-rocks-demo/blob/49568f58b777bd4e39cba7623ad70589fb37a93f/checkpoint/rockcraft.yaml#L27). This must _kill_ the current PetClinic instance and also generate the checkpoint data. You must find this in the main terminal window:
```
2024-10-03T18:25:34.363Z [petclinic] /scripts/start.sh: line 5: 10015 Killed /usr/bin/java -XX:CRaCCheckpointTo=/var/lib/pebble/default/crac-files -jar /jars/spring-petclinic.jar
2024-10-03T18:25:38.871Z [pebble] Service "petclinic" stopped unexpectedly with code 137
```
Note: pebble will start another instance of the application after 500ms.

#### Step 7: Prepare for creation of the restorer Rock

##### Copy the spring-petclinic.jar
Before we kill the checkpointer docker container, let's copy the spring-petclinic.jar file generated by the maven build. In the other terminal window:
```
cd openjdk-crac-rock-demo/checkpoint
sudo docker cp springboot-petclinic:/jars/spring-petclinic.jar /tmp/spring-petclinic.jar
sudo cp /tmp/snap-private-tmp/snap.docker/tmp/spring-petclinic.jar .
```
The third command above is to cater to some unique behaviour of the docker snap. Nevertheless, you must have the spring-petclinic.jar in the PWD at the end of it.

##### Clean and move the checkpoint data
Kill the checkpointer container using CTRL-C. You must find a directory named `data` in the PWD. Delete the dump4.log file from this directory.
```
sudo rm data/dump4.log
```
Next move the `data` directory and the `spring-petclinic.jar` file to the `restore` directory.
```
mv data spring-petclinic.jar ../restore
```
#### Step 8: Create the restorer Rock
Change the directory to restore and run `rockcraft pack`.
```
cd ../restore
rockcraft pack
```
This must create a rock named `spring-petclinic-restorer_0.0.1_amd64.rock`.

#### Step 9: Copy the restorer rock as a Docker image to the docker-daemon
Similar to step 4, use skopeo to copy the rock as a Docker image to the docker-daemon.
```
sudo /snap/rockcraft/current/bin/skopeo --insecure-policy copy oci-archive:spring-petclinic-restorer_0.0.1_amd64.rock docker-daemon:spring-petclinic-restorer:0.0.1
```

#### Step 10: Run "fast-start" SpringBoot PetClinic using the restorer Docker image
The restorer rock has a [petclinic-restore](https://github.com/pushkarnk/openjdk-crac-rocks-demo/blob/49568f58b777bd4e39cba7623ad70589fb37a93f/restore/rockcraft.yaml#L21) service which restores the PetClinic application using OpenJDK CRaC. Now, lets "fast-start" the PetClinic application through this service:
```
sudo docker run \
  -p 8080:8080 \
  --privileged  \
  --rm --name springboot-petclinic-restorer \
  spring-petclinic-restorer:0.0.1 \
  --args petclinic-restore \; --verbose start petclinic-restore
```
Two things to note in the above command:
 - The service being started is named petclinic-restore (like it was petclinic in the checkpointing run)
 - We need the highly undesirable --privileged option because the list of capabilities needed for restoring is quite long!

You must now find a "fast-start" version of PetClinic up in less than 100ms! Try accessing http://localhost:8080 again.

**That's all!**

### Limitations
#### Restoring needs --privileged
The "restore" action needs a [long list of capabilities](https://github.com/checkpoint-restore/criu/issues/684#issuecomment-486882692). I have used --privileged to keep things simple. But, this will not be acceptable in production. Just to make it a little less unacceptable we could stuff all of these capabilities in a docker-compose.yaml and use docker-compose to bring the container up.

#### PID collisions and a way to avoid them
When CRIU restores a process it reuses the same PID as that of the checkpointed process. In a container, this can cause [PID collisions](https://docs.azul.com/core/release/july-2023/crac/crac-debugging#restore-conflict-of-pids) because a tree of processes is being run during restore. It is very likely for "fixed" PID, of the process being restored, to collide with that of a process used in the restore process. We have an [awkard work-around](https://github.com/pushkarnk/openjdk-crac-rocks-demo/blob/main/checkpoint/scripts/start.sh#L2) to make sure the checkpointed process has a large PID!
