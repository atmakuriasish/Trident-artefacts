CXX=g++
CXXFLAGS=-std=c++11 -fopenmp

TARGETS=bfs

all: $(TARGETS)

$(TARGETS):
	$(CXX) $(CXXFLAGS) -o $@ main.cpp

clean:
	rm $(TARGETS) stat.log thp.txt pf* app* err* access* perf* main bfs
