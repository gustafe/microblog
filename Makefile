HOME=/home/gustaf
BIN=$(HOME)/prj/Microblog
TEMPLATES=$(BIN)/templates

.phony: build

content.in: *.md
	cat $^ > $@

build: content.in $(TEMPLATES)/*.tt
	@perl $(BIN)/generate.pl content.in

