#!/usr/bin/env perl

###
# Original develloped by Marc Hoeppner
# Modified by Jacques Dainat
# 2015/03
###

use Carp;
use strict;
use Getopt::Long;
use Scalar::Util qw(openhandle);
use Bio::Tools::GFF;
use Time::Piece;
use Time::Seconds;
use Data::Dumper;
use lib $ENV{ANDREASCODE};
use Private::Bio::IO::GFF;
use URI::Escape;

my $usage = qq{
perl my_script.pl
  Getting help:
    [--help]

  Input:
    [--gff filename]
        The name of the file to read.

    [--blast filename]
        The list of the all-vs-all blast file (outfmt 6, blastp)

  Ouput:
    [--outfile filename]
        The name of the output file. By default the output is the
        standard output
};

my $outfile = undef;
my $gff     = undef;
my $blast   = undef;
my $help;

GetOptions( "help"      => \$help,
            "gff=s"     => \$gff,
            "blast=s"   => \$blast,
            "outfile=s" => \$outfile );

# Print Help and exit
if ($help) {
    print $usage;
    exit(0);
}

# Open Input gff3 file #
my $ref_istream = IO::File->new();
$ref_istream->open( $gff, 'r' ) or
  croak( sprintf( "Can not open '%s' for reading: %s", $gff, $! ) );
my $ref_in = Private::Bio::IO::GFF->new( istream => $ref_istream );

# Open Output files #
my $ostream = IO::File->new();
if ($outfile) {
    $ostream->open( $outfile, 'w' ) or
      croak( sprintf( "Can not open '%s' for writing %s", $outfile, $! ) );
}
else {
    $ostream->fdopen( fileno(STDOUT), 'w' ) or
      croak( sprintf( "Can not open STDOUT for writing: %s", $! ) );
}
my $out = Private::Bio::IO::GFF->new( ostream => $ostream );

#### MAIN ####

# Read killlist #
my $killlist = parse_blast($blast);

# Read mRNA feature from the GFF file.
my @mRNA;
while ( my $feature = $ref_in->read_feature() ) {
    if ( lc( $feature->feature_type() ) eq 'mrna' ) {
        push( @mRNA, $feature );
    }
}

# Unlink all mRNA specified by the kill-list from their (gene-) parents.
foreach my $mRNA_feature (@mRNA) {
    my $id = $mRNA_feature->get_attribute('ID');
    if ( exists( $killlist->{$id} ) ) {
        $mRNA_feature->remove_parent();
    }
}

# Write the remaining things to output
my %genes_written;
foreach my $mRNA_feature (@mRNA) {
    my $id = $mRNA_feature->get_attribute('ID');
    if ( defined( $mRNA_feature->parent() ) ) {
        my $gene_id = $mRNA_feature->parent()->get_attribute('ID');
        if ( !exists( $killlist->{$id} ) &&
             !exists( $genes_written{$gene_id} ) )
        {
            $out->write_feature_group( $mRNA_feature->parent() );
            $genes_written{$gene_id} = 1;
        }
    }
}

# --------------

sub parse_blast
{
    my %answer;
    my %moreThanOneTest;
    my %duo_answer;
    my %hashAns;
    my $infile = shift;
    my $cpt2   = 0;
    # This is one way to open a file...
    open( my $IN, '<', $infile ) or
      die "FATAL: Can't open BLAST file: $infile for reading.\n$!\n";

    # Streaming the file, line by line
    while (<$IN>) {
        chomp;
        my $line = $_;

        my @elements = split( "\t", $line );

        my ( $query, $target, $score ) = @elements[ 0 .. 2 ];

        # Matches that we need to remove
        if ( $query ne $target and $score > 80.0 ) {
            ####### <<<<<<<<<<<<<<<<<<<< HERE THE BLAST VALUE CONSIDERED
            my $id      = "$query$target";
            my $idInver = "$target$query";

            if ( ( !exists( $hashAns{$id} ) ) && ( !exists( $hashAns{$idInver} ) ) )
            {    # avoid redundance info
                $hashAns{$id}++;
                $cpt2++;

                # keep the 2 ids We will then remove one randomly
                $duo_answer{$target} = [ $target, $query ];

                $moreThanOneTest{$target}++;
                $moreThanOneTest{$query}++
                  ;    # Allows to detect mRNA present more than 1 times
                       # (In this case they will be selected in priority
                       # during step 3)
            }

        }
    } ## end while (<$IN>)

    # We should close the file to make sure that the transaction
    # finishes cleanly.
    close($IN);

    #print "$cpt2\n";

    # Detect case to remove absolutely to select in a tuple this one if
    # the other we can keep it
    my %caseToAvoid;
    my $cpt = 0;
    foreach my $key ( keys %moreThanOneTest ) {

        if ( $moreThanOneTest{$key} > 1 ) {
            $caseToAvoid{$key}++;
            my $valueUnEsc = uri_unescape($key);
            $answer{$valueUnEsc}++;    # name from blast must be unescape
            $cpt++;
        }
    }
    #print "We will remove $cpt\n";

    ## Step3
    my $cptCount = 0;
    my $removed  = 0;

    # We will keep one of the tuple
    foreach my $key ( keys %duo_answer ) {
        my ( $val1, $val2 ) = @{ $duo_answer{$key} };
        if ( ( !exists( $caseToAvoid{$val1} ) ) and
             ( !exists( $caseToAvoid{$val2} ) ) )
        {    # case remove one randomly
            my $valueUnEsc = uri_unescape($val1);
            $answer{$valueUnEsc}++;    # name from blast must be unescape
            $cptCount++;
        }
    }

    #print "We will removed $cptCount more.\n";
    my $nbremove = keys %answer;
    print "$nbremove gene will be removed !\n";

    return \%answer;
} ## end sub parse_blast


=head1 NAME
 
gff_filter_by_mrna_id.pl
The script aims to remove from a gff file all the mRNA that have a similarity over THRESHOLD with another mRNA. This is typically useful when creating a list of MRNA to use to train abinitio gene finder. 
A reciprocal blast of the sequences need to have been performed prior to the use of this script in order to get the blastp input file.

=head1 SYNOPSIS

    ./gff_filter_by_mrna_id.pl --gff=infile.gff3 --blast blastfile --outfile outFile
    ./gff_filter_by_mrna_id.pl --help

=head1 OPTIONS

=over 8

=item B<--gff>

Input GFF3 file correponding to gene build.

=item B<--blast> 

The list of the all-vs-all blast file (outfmt 6, blastp)

=item  B<--outfile>

The name of the output file. By default the output is the standard output.

=item B<--help> or B<-h>

Display this helpful text.

=back

=cut
