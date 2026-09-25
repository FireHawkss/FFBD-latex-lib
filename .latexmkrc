# LuaLaTeX is required by tikzffbd, including for latexmk's -pdf recipe.
use Cwd qw(getcwd);
my $package_dir = getcwd();
$ENV{"TEXINPUTS"} = "$package_dir:" . ($ENV{"TEXINPUTS"} // "");
$pdflatex = 'lualatex -no-shell-escape %O %S';
