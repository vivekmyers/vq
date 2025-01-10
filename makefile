BIN = /usr/local/bin

install: $(BIN)/vq

$(BIN)/%: %.sh
	cp $< $@
	chmod 755 $@
