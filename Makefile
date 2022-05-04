HOME=/home/gustaf
BIN=$(HOME)/microblog
TEMPLATES=$(BIN)/templates
CONTENT=$(BIN)/Content

.phony: build

$(CONTENT)/all: $(CONTENT)/*.md
	@cat $^ > $@

build: $(CONTENT)/all $(TEMPLATES)/*.tt
	@perl $(BIN)/generate.pl $(CONTENT)/all

