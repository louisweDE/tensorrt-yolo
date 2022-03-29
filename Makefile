SHELL:=/bin/bash
CUR_DIR=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

detect:
	cd /usr/local/src/tkDNN/build && ./demo demoConfig.yml

builder:
	echo "build Builder"

	docker build . -t tensorrt-yolo-builder -f DockerfileBuilder

	echo "start Builder"

	xhost +

	docker run -it --net=host --runtime nvidia -e DISPLAY=$DISPLAY \
		-v /tmp/.X11-unix/:/tmp/.X11-unix \
		-v $(CUR_DIR)/opencv3/:/usr/local/src/opencv_build/ \
		-v $(CUR_DIR)/tkdnn3/:/usr/local/tkdnn/ \
		-v $(CUR_DIR)/tkdnn_build/:/usr/local/src/tkDNN/build/ \
		--device /dev/video0 \
		tensorrt-yolo-builder /bin/sh -c "ls /usr/local/src/ && make prepareRuntime"

removeBuilder:
	docker image rm tensorrt-yolo-builder
	rm -r $(CUR_DIR)/opencv3
	rm -r $(CUR_DIR)/tkdnn3
	rm -r $(CUR_DIR)/tkdnn_build

compileTensorNetwork:
	cd /usr/local/src/tkDNN/build && ./test-yolo4x

compileOpencv:
	echo "build opencv"
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
    		../opencv

	cd /usr/local/src/opencv_build && ninja -j12 \
    		&& ninja install -j12 \
    		&& ninja package -j12


compileTkdnn:
	echo "build tkdnn"

	mkdir -p /usr/local/src/tkDNN/build
	cd /usr/local/src/tkDNN/build && cmake \
    		-G Ninja \
    		-D CMAKE_INSTALL_PREFIX=/usr/local/tkdnn \
    		/usr/local/src/tkDNN

	cd /usr/local/src/tkDNN/build && ninja -j4 \
		&& ninja install -j4



prepareRuntime: compileOpencv compileTkdnn compileTensorNetwork


runtime:
	echo "build runtime"
	docker build . -t tensorrt-yolo -f DockerfileRuntime

start:
	xhost +

	docker run -it --rm --net=host --runtime nvidia \
		-e DISPLAY=$DISPLAY \
		-v /tmp/.X11-unix/:/tmp/.X11-unix \
		--device /dev/video0 \
		--volume="$$HOME/.Xauthority:/home/developer/.Xauthority:rw" \
		tensorrt-yolo

