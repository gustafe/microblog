HOME=/home/gustaf
BIN=$(HOME)/prj/Microblog
TEMPLATES=$(BIN)/templates
CONTENT=$(BIN)/Content

.phony: build

$(CONTENT)/all: $(CONTENT)/*.md
	@cat $^ > $@

build: $(CONTENT)/all $(TEMPLATES)/*.tt
	@perl $(BIN)/generate.pl $(CONTENT)/all

