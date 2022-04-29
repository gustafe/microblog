HOME=/home/gustaf
BIN=$(HOME)/prj/Microblog
TEMPLATES=$(BIN)/templates

.phony: build

build: content.md $(TEMPLATES)/*.tt
	@perl $(BIN)/generate.pl content.md

