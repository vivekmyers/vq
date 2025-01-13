BIN = $(if $(CONDA_PREFIX),$(CONDA_PREFIX)/bin,/usr/local/bin)

install: $(BIN)/vq $(BIN)/ccolumn

$(BIN)/%: %.sh
	cp $< $@
	chmod 755 $@

$(BIN)/%: %.pl
	cp $< $@
	chmod 755 $@
