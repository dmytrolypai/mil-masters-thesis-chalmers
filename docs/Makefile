all: planning notes langs
planning: Planning.md
	pandoc --variable mainfont=Palatino --variable fontsize=12pt --latex-engine=xelatex --parse-raw -t latex -s Planning.md > Planning.tex
	xelatex Planning.tex
	bibtex  Planning.aux
	xelatex Planning.tex
	xelatex Planning.tex
	rm -f Planning.aux Planning.bbl Planning.blg Planning.log Planning.out Planning.tex
notes: Notes.md
	pandoc --variable mainfont=Palatino --variable fontsize=12pt --variable geometry:margin=1in Notes.md --latex-engine=xelatex -o Notes.pdf
mil: MILNotes.md MIL.md
	pandoc --variable mainfont=Palatino --variable fontsize=12pt --variable geometry:margin=1in MILNotes.md --latex-engine=xelatex -o MILNotes.pdf
	pandoc --variable mainfont=Palatino --variable monofont=Monaco --variable mathfont=Monaco --variable fontsize=11pt --variable geometry:margin=1in MIL.md --latex-engine=xelatex --template=template.latex -o MIL.pdf
funlang: FunLangNotes.md FunLang.md
	pandoc --variable mainfont=Palatino --variable fontsize=12pt --variable geometry:margin=1in FunLangNotes.md --latex-engine=xelatex -o FunLangNotes.pdf
	pandoc --variable mainfont=Palatino --variable monofont=Monaco --variable mathfont=Monaco --variable fontsize=11pt --variable geometry:margin=1in FunLang.md --latex-engine=xelatex --template=template.latex -o FunLang.pdf
oolang: OOLangNotes.md OOLang.md
	pandoc --variable mainfont=Palatino --variable fontsize=12pt --variable geometry:margin=1in OOLangNotes.md --latex-engine=xelatex -o OOLangNotes.pdf
	pandoc --variable mainfont=Palatino --variable monofont=Monaco --variable mathfont=Monaco --variable fontsize=11pt --variable geometry:margin=1in OOLang.md --latex-engine=xelatex --template=template.latex -o OOLang.pdf
langs: mil funlang oolang
clean:
	rm -f Planning.aux Planning.pdf Planning.log Planning.synctex.gz
	rm -f Notes.aux Notes.pdf Notes.log Notes.synctex.gz
	rm -f MILNotes.aux MILNotes.pdf MILNotes.log MILNotes.synctex.gz
	rm -f FunLangNotes.aux FunLangNotes.pdf FunLangNotes.log FunLangNotes.synctex.gz
	rm -f OOLangNotes.aux OOLangNotes.pdf OOLangNotes.log OOLangNotes.synctex.gz
	rm -f MIL.aux MIL.pdf MIL.log MIL.synctex.gz
	rm -f FunLang.aux FunLang.pdf FunLang.log FunLang.synctex.gz
	rm -f OOLang.aux OOLang.pdf OOLang.log OOLang.synctex.gz
