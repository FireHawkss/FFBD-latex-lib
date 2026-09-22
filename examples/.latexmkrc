# Let repository examples find the package sources one directory above when
# latexmk (including the VS Code LaTeX Workshop recipe) builds from this folder.
$ENV{"TEXINPUTS"} = "..:" . ($ENV{"TEXINPUTS"} // "");
