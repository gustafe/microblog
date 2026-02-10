HOME=/home/gustaf
BIN=$(HOME)/microblog
TEMPLATES=$(BIN)/templates
STYLES=$(BIN)/styles
CONTENT=$(BIN)/Content
WEBFILES=$(HOME)/public_html/m
FEDI=$(HOME)/prj/Post-to-fedi

.phony: build
.phony: css
.phony: read-feed
.phony: post-to-fedi
.phony: read-and-post

$(CONTENT)/all: $(CONTENT)/*.md
	@cat $^ > $@

publish: $(CONTENT)/all $(TEMPLATES)/*.tt 
	@perl $(BIN)/generate.pl $(CONTENT)/all
	npx -q pagefind --site $(WEBFILES)/

update: $(CONTENT)/all
	@perl $(BIN)/generate.pl $(CONTENT)/all

css: $(STYLES)/*.css
	cp $(STYLES)/*.css $(WEBFILES)/

read-feed:
	perl $(FEDI)/read-feed.pl

post-to-fedi:
	@perl $(FEDI)/post-to-fedi.pl

read-and-post:
	read-feed
	post-to-fedi
