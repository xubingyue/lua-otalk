# Nigels wizzzy "simple" makefile
# ###################################################################
#
LIBS=-llua -ldl
CXXFLAGS=-g -Wall -Wno-deprecated -std=c++11
EXECUTABLE=example
SOURCES=otalk.cpp example.cpp
OBJDIR=./

# ###################################################################


OBJECTS=$(addprefix $(OBJDIR)/,$(SOURCES:.cpp=.o))

.PHONY: all
all:	$(SOURCES) $(EXECUTABLE)

$(EXECUTABLE):	$(OBJECTS)
	$(CXX) $(LDFLAGS) $(OBJECTS) $(LIBS) -o $@

# Object files
# #############
#
$(OBJDIR)/%.o: %.cpp | $(OBJDIR)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(OBJDIR):
	mkdir -p $(OBJDIR)

