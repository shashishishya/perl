#!perl
#
###############################################################################
# Change Log
#
# 2011-11-14 Changed processing of inactive designation tracks.
# 2013-09-20 jfs - Updated code to make it more readable
#
###############################################################################
use lib qw(/home/jspooner/apache/appic2017/web/local/lib/perl5/i686-linux/ /home/jspooner/apache/appic2017/local/lib/perl5 /home/jspooner/apache/appic2017/web/designation_script);
use DBI;
use Data::Dumper;
use POSIX qw(strftime);
use strict;
use warnings;
die "$0 <tab delimited designation import file>\n" unless $ARGV[0];
my $file = $ARGV[0];
my $added_admiss = {};
my $base = $file;
my %dead;
my $db = [ 'DBI:ODBC:appic2017_desig', 'appic2017', 'appic2017' ];
my $dbh = DBI->connect(@$db);
my $dz = $dbh->selectall_arrayref("select site_number from designationlookup where deadline < GetDate() and change_date IS NULL");
$base =~ s/\.\w*$//g;
$dbh->{LongReadLen} = 250000;
my $designations = $dbh->selectall_arrayref(
"SELECT [id], [designation_name], [state], [deadline], [hard_deadline], [comments], [city], [site_number]
FROM [DesignationLookup]", { Slice => {} }
);
foreach my $d (@$dz) {
$dead{ $d->[0] } = 1;
}
my %killme;
my %codes;
my %names;
my %cities;
my %states;
foreach my $d (@$designations) {
$codes{ $d->{site_number} } = 1;
$killme{ $d->{site_number} } = 1;
$names{ $d->{site_number} } = $d->{designation_name};
$cities{ $d->{site_number} } = $d->{city};
$states{ $d->{site_number} } = $d->{state};
}
open IN, $file;
open N, "> $base.new.txt";
open U, "> $base.update.txt";
open D, "> $base.delete.txt";
open UND, "> $base.reopen.txt";
open AD, "> $base.newadmin.txt";
open TRK, "> $base.tracks.txt";
open SQL, "> $base.sql.txt";
my @outdata;
while (<IN>) {
chop;
chomp;
my $line = $_;
next if ( ( $line =~ /NUMBER/ )
&& ( $line =~ /NAME/ )
&& ( $line =~ /CITY/ )
&& ( $line =~ /PROV/ )
&& ( $line =~ /MEMBER/ )
&& ( $line =~ /APA/ )
&& ( $line =~ /CPA/ ) );
my @data = split( "\t", $line );
foreach my $d (@data) {
$d =~ s/^"(.*)"$/$1/g;
}
push @outdata, [ $line, \@data ];
}
@outdata = cleanse_track_data(@outdata);
open CLEAN, "> clean.txt";
foreach my $o (@outdata) {
print CLEAN join( "\t", $o->[0] ) . "\r\n";
}
close CLEAN;
foreach my $ardata (@outdata) {
my $line = $ardata->[0];
my @data = @{ $ardata->[1] };
map s/^[Y|A]$/Yes/g , @data;
map s/^N$/No/g, @data;
my $tracks = $ardata->[2];
my $new_designation = 0;
if ( exists( $dead{ $data[0] } ) ) {
print UND $line . "\r\n";
print SQL "\r\n--THIS UPDATE UNEXPIRES $data[1] in $data[3]!\r\n";
print SQL "UPDATE [DesignationLookup] SET [deadline] = '2222-12-12' WHERE [site_number] = '$data[0]'" . "\r\n";
}
if ( exists( $codes{ $data[0] } ) ) {
if ( ( $data[1] ne $names{ $data[0] } ) ||
( $data[2] ne $cities{ $data[0] } ) ||
( $data[3] ne $states{ $data[0] } ) )
{
print U $line . "\r\n";
$data[1] =~ s/'/''/g;
$data[2] =~ s/'/''/g;
$data[3] =~ s/'/''/g;
print SQL "UPDATE [DesignationLookup] SET [designation_name] = '$data[1]', [city] = '$data[2]', [state] = '$data[3]', [APPI_Member] = '$data[4]', [APA_Accredited] = '$data[5]' WHERE [site_number] = '$data[0]'\r\n";
delete( $killme{ $data[0] } );
}
else {
delete( $killme{ $data[0] } );
}
}
else {
print N $line . "\r\n";
$data[1] =~ s/'/''/g;
$data[2] =~ s/'/''/g;
$data[3] =~ s/'/''/g;
print SQL "INSERT INTO [DesignationLookup] ([designation_name],[state],[deadline],[comments],[city],[site_number],[APPI_Member],[APA_Accredited]) VALUES ('$data[1]','$data[3]','12/12/2222','','$data[2]','$data[0]','$data[4]','$data[5]')" . "\r\n";
my $x = admissionsql( $dbh, @data );
print SQL $x->[0];
print AD $x->[1];
}
my $tracksql = handle_tracks( $data[0], $dbh, $tracks );
if ( $tracksql->{SQL} ) {
print SQL $tracksql->{SQL};
}
if ( $tracksql->{TRK} ) {
print TRK $tracksql->{TRK};
}
}
close IN;
foreach my $k ( keys(%killme) ) {
unless ( exists( $dead{$k} ) ) {
print D $k . "\r\n";
print SQL "UPDATE [DesignationLookup] SET [deadline] = '1980-02-17', [change_date] = NULL WHERE [site_number] = '$k'" . "\r\n";
}
}
close AD;
close SQL;
close D;
close U;
close N;
close UND;
close TRK;
$dbh->disconnect;
sub makepass {
my $password;
my $_rand;
my $password_length = 6;
if ( !$password_length ) {
$password_length = 10;
}
my @chars = split(
" ",
"a b c d e f g h i j k l m n o
p q r s t u v w x y z
0 1 2 3 4 5 6 7 8 9"
);
srand;
for ( my $i = 0; $i <= $password_length; $i++ ) {
$_rand = int( rand 36 );
$password .= $chars[$_rand];
}
return uc($password);
}
sub admissionsql {
foreach my $zzz (@_) {
$zzz =~ s/'/''/g;
}
my ( $dbh, $number, $name, $city, $state, $member, $apa, $cpa, $ocontact, $email ) = @_;
my ( $first, $last );
#try really really hard to clean up the name... this isn't guaranteed
my $contact = $ocontact;
$contact =~ s/^(Dr\.?\s*)?//g;
$contact =~ s/\,.*$//g;
if ( $contact =~ /(.*)\s+(.*)/ ) {
$first = $1;
$last = $2;
}
else {
$first = $contact;
$last = "fillin";
}
my $admiss = $dbh->selectall_arrayref( "SELECT * from admissions where admissions_username = '$number" . "_01'\r\n",, { Slice => {} } );
my $password = makepass();
my $bar = [];
return [ "", "" ] if ( $added_admiss->{$number} );
$added_admiss->{$number} = 1;
if ( $admiss->[0] ) {
my $amo = $admiss->[0];
if ( $amo->{admissions_email} eq $email ) { return [ "", "" ]; }
push @$bar, "\r\n--Updating admissions user for $ocontact at site $number\r\nUPDATE [Admissions] \r\n" . " SET admissions_firstname = " . $dbh->quote($first) . ", admissions_lastname = " . $dbh->quote($last) . ", admissions_email = " . $dbh->quote($email) . ", admissions_password = " . $dbh->quote($password) . " WHERE admissions_username = '$number" . "_01'\r\n";
push @$bar, "Updating admin $email FOR SITE $number has this login -> u: " . $number . "_01 p: $password\r\n";
return $bar;
}
push @$bar, "\r\n--Adding admissions user for $ocontact at site $number\r\nINSERT INTO [Admissions] \r\n ([admissions_firstname],[admissions_lastname],[admissions_username],[admissions_password],[admissions_email],[active],[designation_lookup_id],[date_added],[phone],[can_adduser])\r\n SELECT TOP 1 '$first','$last','$number" . "_01','$password','$email',1, id ,GetDate(),'',1 FROM [DesignationLookup] WHERE site_number = '$number'\r\n";
push @$bar, "Adding admin $email FOR SITE $number has this login -> u: " . $number . "_01 p: $password\r\n";
return $bar;
}
sub handle_tracks {
my ( $sitenumber, $dbh, $tracks, $newup ) = @_;
my %rval;
$rval{SQL} = "";
$rval{TRK} = "";
my $dbtracks = $dbh->selectall_arrayref(
"SELECT t.*
FROM designationLookup dl
INNER JOIN tracks t ON t.designation_lookup_id = dl.id
WHERE site_number = ?", {}, $sitenumber
);
my %untouched = map { $_ => 1 } keys(%$tracks);
delete $untouched{PROGCODE};
foreach my $row (@$dbtracks) {
if ( exists( $untouched{ $row->[4] } ) ) {
delete( $untouched{ $row->[4] } );
my $track = $tracks->{ $row->[4] };
#update
next if ( $track eq $row->[2] );
$track =~ s/\015//g;
$track =~ s/"//g;
my $isql = "UPDATE dbo.Tracks set track_name = " . $dbh->quote($track) . " WHERE prog_code = " . $row->[4] . " AND designation_lookup_id = (SELECT id from DesignationLookup WHERE site_number = $sitenumber)";
$rval{SQL} = $rval{SQL} . "\r\n--Updating track $track with id " . $row->[4] . " and site number $sitenumber\r\n$isql\r\n";
$rval{TRK} = $rval{TRK} . "Adding track $track with id " . $row->[4] . "\r\n";
}
else {
my $track = $tracks->{ $row->[0] };
# The $killtrack variable below is a temporary fix to deter applicants from selecting tracks
# which no longer exist, but which currently remain in the database. Since this was addressed
# mid-cycle, it was decided not to make any DDL changes to the
# database for a permanent fix. A permanent solution is planned for next cycle.
my $killtrack = '<font color="red">&nbsp; (no longer available)</font>';
$rval{SQL} = $rval{SQL} . "\r\n--TODO: DELETE track with id " . $row->[0] . "\r\n";
my $isql = "UPDATE dbo.Tracks set track_name = track_name + " . $dbh->quote($killtrack) . " WHERE RIGHT(track_name,27) != 'no longer available)</font>' AND track_id = " . $row->[0];
$rval{SQL} = $rval{SQL} . "\r\n--Updating track with id " . $row->[0]
. " and site number $sitenumber\r\n$isql\r\n";
$rval{TRK} = $rval{TRK} . "WE HAVE A REQUEST TO DELETE TRACK WITH ID " . $row->[0] . "\r\n";
}
}
foreach my $trkid ( keys(%untouched) ) {
my $track = $tracks->{$trkid};
#Create!
$track =~ s/\015//g;
my $isql = "INSERT INTO dbo.Tracks(designation_lookup_id,track_name,description,prog_code)\r\nSELECT TOP 1 id," . $dbh->quote($track) . ",NULL,$trkid FROM dbo.DesignationLookup WHERE site_number=$sitenumber";
$rval{SQL} = $rval{SQL} . "\r\n--Adding track $track with id $trkid to site number $sitenumber\r\n$isql\r\n";
$rval{TRK} = $rval{TRK} . "Adding track $track with id $trkid to site number $sitenumber\r\n";
}
return \%rval;
}
sub cleanse_track_data {
my @alldata = @_;
my @rval;
my %hrval;
my @order;
foreach my $d (@alldata) {
my $line = $d->[0];
my $data = $d->[1];
my $who = $data->[0];
my $track_id = $data->[9];
my $trackname = $data->[10];
unshift( @order, $who );
pop(@$data);
pop(@$data);
if ( exists( $hrval{$who} ) ) {
$hrval{$who}->[0] = $hrval{$who}->[0] . "\t$track_id\t\"$trackname\"";
$hrval{$who}->[2]->{$track_id} = $trackname;
}
else {
$hrval{$who} = [ $line, $data, { $track_id => $trackname } ];
}
}
foreach my $o (@order) {
if ( $hrval{$o} ) {
push @rval, $hrval{$o};
delete( $hrval{$o} );
}
}
return @rval;
}
