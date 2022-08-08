HOME=/home/gustaf
BIN=$(HOME)/microblog
TEMPLATES=$(BIN)/templates
STYLES=$(BIN)/styles
CONTENT=$(BIN)/Content
WEBFILES=$(HOME)/public_html/m
.phony: build
.phony: css

$(CONTENT)/all: $(CONTENT)/*.md
	@cat $^ > $@

build: $(CONTENT)/all $(TEMPLATES)/*.tt 
	@perl $(BIN)/generate.pl $(CONTENT)/all

css: $(STYLES)/*.css
	cp $(STYLES)/*.css $(WEBFILES)/
