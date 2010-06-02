pxemultiboot.pdf: pxemultiboot.rd.txt.utf8 booting.png pxemultiboot.png
	rabbit -p -o $@ $<

%.png: %.dot
	dot -Tpng -o $@ $<
