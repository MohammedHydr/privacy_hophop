# SPDX-License-Identifier: Apache-2.0

BMV2_SWITCH_EXE = simple_switch_grpc
TOPO = pod-topo/topology.json

# Compile privacy.p4
P4C      = p4c-bm2-ss
P4SRC    = privacy.p4
JSON     = build/privacy.json
P4INFO   = build/privacy.p4.p4info.txtpb

all: run

$(JSON): $(P4SRC)
	mkdir -p build
	$(P4C) --p4v 16 --p4runtime-files $(P4INFO) -o $(JSON) $(P4SRC)
	# IMPORTANT: Create alias copies so sX-runtime.json files find them!
	cp build/privacy.p4.p4info.txtpb build/basic.p4.p4info.txtpb
	cp build/privacy.json            build/basic.json

run: $(JSON)
	mkdir -p pcaps logs
	sudo PATH=/home/p4/tutorials/vm-ubuntu-24.04:/home/p4/src/behavioral-model/tools:/usr/local/bin:/home/p4/src/p4dev-python-venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:/snap/bin \
	  PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python \
	  python3 ../../utils/run_exercise.py \
	    -t $(TOPO) -j build/privacy.json -b $(BMV2_SWITCH_EXE)

stop:
	sudo `which mn` -c

clean: stop
	rm -f *.pcap
	rm -rf build pcaps logs