use strict;
use warnings;
use lib qw(
/home/jspooner/apache/appic2017/web/local/lib/perl5
);
use Net::SFTP::Foreign;
use Net::SFTP::Foreign::Attributes;
use DBI;
use Data::Dumper;
use DateTime;
my $user = 'aapiadmin';
my $password = 'NMSapc2012';
# Establishing the connection to the "www.enterlist.com" site.
my $sftp = Net::SFTP::Foreign->new( host => "www.enterlist.com", user => $user, password => $password, more => [ -o => 'StrictHostKeyChecking no' ] );
$sftp->die_on_error("Unable to establish SFTP connection");
my @files = $sftp->glob( "*.xls", names_only => 1 );
# Creating file name
my $today = 'SITE'.DateTime->today();
$today =~ s/-//g;
$today =~ s/T0.*?$//g;
my $today_file = $today.'.xls';
system("mkdir $today");
my $cwd = `pwd`;
$cwd =~s/\n/\/$today\//g;
# To fetch the file from www.enterlist.com
$sftp->get( $files[0], $cwd.$today_file ) or die "file transfer failed: " . $sftp->error;
