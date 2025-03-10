CXX=g++
CXXFLAGS=-std=c++11 -fopenmp

TARGETS=pgr

all: $(TARGETS)

$(TARGETS):
	$(CXX) $(CXXFLAGS) -o $@ main.cpp

clean:
	rm $(TARGETS) main pgr
