CXX=g++
CXXFLAGS=-std=c++11 -O3 -Wno-unused-result

TARGETS=bfs

all: $(TARGETS)

$(TARGETS):
	$(CXX) $(CXXFLAGS) -o $@ main.cpp

clean:
	rm $(TARGETS) stat.log thp.txt pf* app* err* access* perf* main bfs
