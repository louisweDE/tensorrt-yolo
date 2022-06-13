SHELL:=/bin/bash
CUR_DIR=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

detect:
	cd /usr/local/src/tkDNN/build && ./demo demoConfig.yml

# Converts a darknet Model to TensorRt network
CFG = $(error CFG FileName not set --> make CFG=<fileName> WEIGHTS=<fileName> NAMES=<fileName> convert)
WEIGHTS = $(error WEIGHTS FileName not set --> make CFG=<fileName> WEIGHTS=<fileName> NAMES=<fileName> convert)
NAMES = $(error NAMES FileName not set --> make CFG=<fileName> WEIGHTS=<fileName> NAMES=<fileNam> convert)
convert:
	@echo exporting darknet Model cfgFile:$(CFG) - weightsFile:$(WEIGHTS)
	cd /usr/local/src/darknet && cp models/$(CFG) models/convert.cfg && cp models/$(WEIGHTS) models/convert.weights && cp models/$(NAMES) models/convert.names
	cd /usr/local/src/darknet && ./darknet export models/convert.cfg models/convert.weights layers
	cd /usr/local/src/tkDNN/build && ./test_darknetToTensorRt

builder:
	@echo "build Builder"

	docker build . -t tensorrt-yolo-builder -f DockerfileBuilder

	@echo "start Builder"

	xhost +

	docker run -it --net=host --runtime nvidia -e DISPLAY=$DISPLAY \
		-v /tmp/.X11-unix/:/tmp/.X11-unix \
		-v $(CUR_DIR)/opencv3/:/usr/local/src/opencv_build/ \
		-v $(CUR_DIR)/tkdnn3/:/usr/local/tkdnn/ \
		-v $(CUR_DIR)/tkdnn_build/:/usr/local/src/tkDNN/build/ \
		-v $(CUR_DIR)/darknet/:/usr/local/src/darknet/ \
		--device /dev/video0 \
		tensorrt-yolo-builder /bin/sh -c "ls /usr/local/src/ && make prepareRuntime"

removeBuilder:
	docker image rm tensorrt-yolo-builder
	rm -r $(CUR_DIR)/opencv3
	rm -r $(CUR_DIR)/tkdnn3
	rm -r $(CUR_DIR)/tkdnn_build

compileDarknet:
	cd /usr/local/src/darknet && make && mkdir layers debug

compileTensorNetwork:
	cd /usr/local/src/tkDNN/build && ./test_yolo4

compileOpencv:
	@echo "build opencv"
	cd /usr/local/src/opencv_build && cmake -G Ninja \
    		-D CMAKE_BUILD_TYPE=RELEASE \
    		-D CMAKE_INSTALL_PREFIX=/usr/local \
    		-D INSTALL_PYTHON_EXAMPLES=OFF \
    		-D INSTALL_C_EXAMPLES=OFF \
    		-D OPENCV_EXTRA_MODULES_PATH='/usr/local/src/opencv_contrib/modules' \
    		-D BUILD_EXAMPLES=OFF \
    		-D WITH_CUDA=ON \
    		-D CUDA_ARCH_BIN='5.3 6.2 7.2' \
    		-D CUDA_ARCH_PTX="" \
    		-D WITH_CUDNN=ON \
    		-D ENABLE_FAST_MATH=ON \
    		-D CUDA_FAST_MATH=ON \
    		-D WITH_CUBLAS=ON \
    		-D WITH_LIBV4L=ON \
    		-D WITH_GSTREAMER=ON \
    		-D WITH_GSTREAMER_0_10=OFF \
    		-D WITH_TBB=ON \
		-D WITH_GTK=ON \
    		-D WITH_VULKAN= ON ../opencv

	cd /usr/local/src/opencv_build && ninja -j12 \
    		&& ninja install -j12 \
    		&& ninja package -j12


compileTkdnn:
	@echo "build tkdnn"

	mkdir -p /usr/local/src/tkDNN/build
	cd /usr/local/src/tkDNN/build && cmake \
    		-G Ninja \
    		-D CMAKE_INSTALL_PREFIX=/usr/local/tkdnn \
    		-D CMAKE_BUILD_TYPE=Release \
		-D ENABLE_OPENCV_CUDA_CONTRIB=ON \
		/usr/local/src/tkDNN

	cd /usr/local/src/tkDNN/build && ninja -j4 \
		&& ninja install -j4



prepareRuntime: compileOpencv compileTkdnn compileTensorNetwork compileDarknet


buildRuntime:
	@echo "build runtime"
	docker build . -t tensorrt-yolo -f DockerfileRuntime

pullRuntime:
	docker pull louiswe/tensorrt-yolo:latest
	docker tag louiswe/tensorrt-yolo:latest tensorrt-yolo

configureForTx2:
	sed -i 's/\/dev\/video0/\/dev\/video1/g' Makefile
	sed -i 's/\/dev\/video0/\/dev\/video1/g' demoConfig.yml

resetConfiguration:
	sed -i 's/\/dev\/video1/\/dev\/video0/g' Makefile
	sed -i 's/\/dev\/video1/\/dev\/video0/g' demoConfig.yml

start:
	xhost +

	docker run -it --rm --net=host --runtime nvidia \
		-e DISPLAY=$DISPLAY \
		-v /tmp/.X11-unix/:/tmp/.X11-unix \
		--device /dev/video0 \
		-v "$$HOME/.Xauthority:/home/developer/.Xauthority:rw" \
		-v $(CUR_DIR)/demoConfig.yml:/usr/local/src/tkDNN/build/demoConfig.yml \
		-v $(CUR_DIR)/layers/:/usr/local/src/darknet/layers/ \
		-v $(CUR_DIR)/debug/:/usr/local/src/darknet/debug/ \
		-v $(CUR_DIR)/models/:/usr/local/src/darknet/models/ \
		tensorrt-yolo

startBuilder:
	xhost +

	docker run -it --rm --net=host --runtime nvidia \
		-e DISPLAY=$DISPLAY \
		-v /tmp/.X11-unix/:/tmp/.X11-unix \
		--device /dev/video0 \
		--volume="$$HOME/.Xauthority:/home/developer/.Xauthority:rw" \
		-v $(CUR_DIR)/tkdnn3/:/usr/local/tkdnn/ \
		-v $(CUR_DIR)/tkdnn_build/:/usr/local/src/tkDNN/build/ \
		-v $(CUR_DIR)/opencv3/:/usr/local/src/opencv_build/ \
		-v $(CUR_DIR)/demoConfig.yml:/usr/local/src/tkDNN/build/demoConfig.yml \
		-v $(CUR_DIR)/darknet/:/usr/local/src/darknet/ \
		-v $(CUR_DIR)/darknetToTensorRt/:/usr/local/src/tkDNN/tests/darknet/darknetToTensorRt.cpp \
		tensorrt-yolo-builder
