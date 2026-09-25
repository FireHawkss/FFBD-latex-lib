# Let repository examples find the package sources one directory above when
# latexmk (including the VS Code LaTeX Workshop recipe) builds from this folder.
$ENV{"TEXINPUTS"} = "..:" . ($ENV{"TEXINPUTS"} // "");
# LaTeX Workshop commonly invokes `latexmk -pdf`. Route that recipe through
# LuaLaTeX, which is the engine required by tikzffbd.
$pdflatex = 'lualatex -no-shell-escape %O %S';
