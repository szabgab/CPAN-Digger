use strict;
use warnings;
use feature 'say';
use Data::Dumper qw(Dumper);

# Create an index.html file for the logs folder

sub main {
    opendir my $dh, "_site/logs" or die;
    my @logs = sort {-M "_site/logs/$b" <=> -M "_site/logs/$a"} grep {/\.log$/} readdir $dh;
    close $dh;

    say Dumper \@logs;
    my $html = <<HTML;
<html>
  <head>
    <title>Logs</title>
 </head>
 <body>
HTML

        $html .= "<ul>\n";
        for my $log (@logs) {
            $html .= qq(<li><a href="$log">$log</a></li>\n);
        }
        $html .= "</ul>\n";

    $html = <<HTML;
$html
  </body>
</html>
HTML


    open my $fh, ">", "_site/logs/index.html" or die;
    print $fh $html
}


main()
