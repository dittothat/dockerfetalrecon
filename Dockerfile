# Set up a docker image for fetalReconstruction
# https://github.com/bkainz/fetalReconstruction
#
# Jeff Stout BCH 20190731
#
# Build with
#
#   docker build -t <name> .
#
# In the case of a proxy (located at 192.168.13.14:3128), do:
#
#    docker build --build-arg http_proxy=http://10.41.13.4:3128 --build-arg https_proxy=https://10.41.13.6:3128 -t fetalrecon .
#
# --no-cache will force a clean build
# 
# To run an interactive shell inside this container, do:
#
#   docker run --gpus all -it fetalrecon /bin/bash 
#
#   docker run --gpus all -it --mount type=bind,source=/neuro/users/jeff.stout/docker/data,target=/data fetalrecon
#
# To pass an env var HOST_IP to container, do:
#
#   docker run -ti -e HOST_IP=$(ip route | grep -v docker | awk '{if(NF==11) print $9}') --entrypoint /bin/bash local/chris_dev_backend
# 
# Docker build cuda library issue:
# the default runtime must be set to nvidia in order to have CUDA libararies mounted during build (see: https://github.com/NVIDIA/nvidia-docker/wiki/Advanced-topics)
# This can be accomplished for the docker 19.03 nvidia-runtime by:
# installing the nvidia-container-runtime package in your host. Then put this inside /etc/docker/daemon.json
# {
#     "runtimes": {
#         "nvidia": {
#             "path": "/usr/bin/nvidia-container-runtime",
#             "runtimeArgs": []
#         }
#     },
#     "default-runtime": "nvidia"
# }

FROM nvidia/cuda:9.1-devel-ubuntu16.04
# https://hub.docker.com/r/nvidia/cuda

# using build command noted above is better pratice
# ENV http_proxy http://10.41.13.4:3128

# ENV https_proxy https://10.41.13.6:3128

# update and install dependencies
RUN         apt-get update \
                && apt-get install -y --no-install-recommends \
                    apt-utils \
                && apt-get install -y --no-install-recommends \
                    software-properties-common \
                    wget \
                    make \
                    git \
                    curl \
                    vim \
                    cmake \
                    gcc \
                    libtbb-dev \
                    libgsl-dev \
                    cmake-curses-gui \
                    libpng-dev

# add cuda samples to the image
# ADD ./samples.tar.gz /usr/local/cuda-9.1

RUN wget https://developer.nvidia.com/compute/cuda/9.1/Prod/cluster_management/cuda_cluster_pkgs_9.1.85_ubuntu1604 -P /usr/src/ \
    && tar -zxvf /usr/src/cuda_cluster_pkgs_9.1.85_ubuntu1604 cuda_cluster_pkgs_ubuntu1604/cuda-cluster-devel-9-1_9.1.85-1_amd64.deb \
    && ar x ./cuda_cluster_pkgs_ubuntu1604/cuda-cluster-devel-9-1_9.1.85-1_amd64.deb data.tar.xz \
    && tar -xJvf data.tar.xz ./usr/local/cuda-9.1/samples \
    && make -C /usr/local/cuda-9.1/samples \
    && rm -r cuda_cluster_pkgs_ubuntu1604 && rm data.tar.xz && rm /usr/src/cuda_cluster_pkgs_9.1.85_ubuntu1604

# this is the relevant fetalReconstruction
# COPY ./fetalReconstruction /usr/src/fetalReconstruction/
RUN git clone https://github.com/bkainz/fetalReconstruction.git /usr/src/fetalReconstruction/

# add boost and install additional libraries
RUN wget https://sourceforge.net/projects/boost/files/boost/1.58.0/boost_1_58_0.tar.bz2 -P /usr/src/ \
    && cd /usr/src/ && tar -xf boost_1_58_0.tar.bz2 \
    && cd /usr/src/boost_1_58_0 \
    && ./bootstrap.sh --with-libraries=program_options,filesystem,system,thread,atomic,chrono,date_time \
    && ./b2 install

# build ZLIB
RUN cd /usr/src/fetalReconstruction/source/IRTKSimple2/nifti/zlib \
    && ./configure && make install

# set up and build the fetalRecon software 
RUN mkdir /usr/src/fetalReconstruction/source/build \
        && mkdir /data \
    && cd /usr/src/fetalReconstruction/source/build 

RUN cd /usr/src/fetalReconstruction/source/build \
    && cmake -DCUDA_SDK_ROOT_DIR:PATH=/usr/local/cuda-9.1/samples -DCUDA_NVCC_FLAGS=-gencode=arch=compute_30,code=sm_35 .. \
    # && cmake -DCUDA_SDK_ROOT_DIR:PATH=/usr/local/cuda-9.1/samples .. \
    # && cmake -DCUDA_SDK_ROOT_DIR:PATH=/usr/local/cuda-9.1/samples -DCUDA_CUDA_LIBRARY:PATH=/usr/lib/x86_64-linux-gnu/libcuda.so .. \
    && make ; exit 0
# the error above is werid. run make again and it is all good, I don't know why
RUN cd /usr/src/fetalReconstruction/source/build \
    && make \
    && cp /usr/src/fetalReconstruction/source/bin/PVRreconstructionGPU /usr/bin \
    && cp /usr/src/fetalReconstruction/source/bin/SVRreconstructionGPU /usr/bin

#############################################################################
# Compute architecture compile flag information for line 97 above. cm_35 is the original device that the code was written for. 
# http://arnon.dk/matching-sm-architectures-arch-and-gencode-for-various-nvidia-cards/
#  https://docs.nvidia.com/cuda/cuda-compiler-driver-nvcc/index.html#gpu-compilation
#  "In fact, --gpu-architecture=arch --gpu-code=code,... is equivalent to --generate-code=arch=arch,code=code,.... "
#  -gencode=arch=compute_70,code=sm_70
#  -gencode=arch=compute_30,code=sm_30 (this was native for the fetal recon intially, I think)

# useful test for PVRreconstructionGPU
# cd /usr/src/fetalReconstruction/data
# PVRreconstructionGPU -o 3TReconstruction.nii.gz -i 14_3T_nody_001.nii.gz 10_3T_nody_001.nii.gz 21_3T_nody_001.nii.gz 23_3T_nody_001.nii.gz -m mask_10_3T_brain_smooth.nii.gz --resolution 1.0
# current error:
# CUDA error at /usr/src/fetalReconstruction/source/reconstructionGPU2/include/reconVolume.cuh:51 code=2(cudaErrorMemoryAllocation) "cudaMalloc((void **)&m_d_data, m_size.x * m_size.y * m_size.z * sizeof(T))" 
# so the GPU actually has no memory left due to python processes...
