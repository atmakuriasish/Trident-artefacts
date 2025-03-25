CXX=g++
CXXFLAGS=-std=c++11 -fopenmp

TARGETS=pgr

all: $(TARGETS)

$(TARGETS):
	$(CXX) $(CXXFLAGS) -o $@ main.cpp

clean:
	rm $(TARGETS) stat.log thp.txt pf.txt main pgr
