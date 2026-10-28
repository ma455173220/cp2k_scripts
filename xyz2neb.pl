#!/usr/bin/perl -w
# This is a "quick and dirty" perl script to generate NEB images for CP2K.
# Hope it works.
#
# Usage: xyz2neb.pl initial.xyz final.xyz N [-c cp2k.inp | a b c]
#   Writes 0.xyz ... N.xyz, linearly interpolated between initial and final geometry.
#   With a cell (-c FILE: &CELL of a CP2K input/restart, a *-1.cell file (last step) or a POSCAR, read with
#   cp2k_inp.py; or three numbers a b c for an orthorhombic cell in Angstrom), every atom moves along the
#   minimum-image displacement, so atoms wrapped across the periodic boundary do not jump through the cell.
use strict;
use warnings;
use POSIX qw(floor);
use Cwd qw(abs_path);
use File::Basename qw(dirname);

my $usage = "Usage: $0 initial.xyz final.xyz N [-c cp2k.inp | a b c]\n";
die $usage if @ARGV < 3;
my $INI=$ARGV[0];
my $FIN=$ARGV[1];
my $num=$ARGV[2];
die "N must be a positive integer.\n$usage" unless $num =~ /^\d+$/ && $num > 0;
my @coord1;
my @coord2;
my @array;
my $line;
my ($i,$j,$k);

# Optional cell (rows = cell vectors a, b, c in Angstrom)
my @cell;
my @rest = @ARGV[3..$#ARGV];
if (@rest == 2 && $rest[0] eq '-c') {
    @cell = read_cp2k_cell($rest[1]);
} elsif (@rest == 3) {
    for (@rest) { die "Cell lengths must be numbers.\n$usage" unless /^[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$/; }
    @cell = ([$rest[0],0,0],[0,$rest[1],0],[0,0,$rest[2]]);
} elsif (@rest) {
    die $usage;
}
my @inv = @cell ? inverse3(\@cell) : ();
if (!@cell) {
    warn "Warning: no cell given; interpolating plain Cartesian coordinates (no minimum image).\n"
       . "         Atoms wrapped across a periodic boundary will move through the cell. Use -c cp2k.inp or a b c.\n";
}

#Read initial and final geometry
@coord1 = read_xyz($INI);
@coord2 = read_xyz($FIN);

# The two geometries must describe the same atoms in the same order
if (@coord1 != @coord2) {
    die "Error: $INI has ".scalar(@coord1)." atoms but $FIN has ".scalar(@coord2)." atoms.\n";
}
die "Error: no atoms read from $INI.\n" unless @coord1;
for $j (0..$#coord1) {
    if (lc($coord1[$j]->[0]) ne lc($coord2[$j]->[0])) {
        die "Error: atom ".($j+1)." is $coord1[$j]->[0] in $INI but $coord2[$j]->[0] in $FIN (atom order must match).\n";
    }
}

# Displacement of every atom (minimum image if a cell is known)
my @disp;
for $j (0..$#coord1) {
    my @d = map { $coord2[$j]->[$_] - $coord1[$j]->[$_] } 1..3;
    if (@cell) {
        # fractional displacement f = d * inv(H), wrap to [-0.5, 0.5), back to Cartesian d = f * H
        my @f = map { my $c = $_; $d[0]*$inv[0][$c] + $d[1]*$inv[1][$c] + $d[2]*$inv[2][$c] } 0..2;
        @f = map { $_ - floor($_ + 0.5) } @f;
        @d = map { my $c = $_; $f[0]*$cell[0][$c] + $f[1]*$cell[1][$c] + $f[2]*$cell[2][$c] } 0..2;
    }
    push @disp, [@d];
}

#Generate geometries
for $i(0..$num){
    my $name=$i.".xyz";
    open (OUT,">","$name")||die "Failed to open $name : $!";
    print OUT scalar @coord1."\n";
    print OUT "Geometry-".${i}."\n";
    for $j (0..@coord1-1){
	@array=();
	for $k(1..3){
	    $array[$k]=$coord1[$j]->[$k]+$disp[$j]->[$k-1]*$i/$num;
	    # with a cell, print fixed decimals (avoids round-off noise such as 4.7e-16 from the wrapping)
	    $array[$k]=sprintf("%.10f",$array[$k]) if @cell;
	}
	print OUT "$coord1[$j]->[0] $array[1] $array[2] $array[3]\n";
    }
    close(OUT);
}

# Read an xyz file. Standard xyz (atom count, comment, atoms) is read by its header;
# otherwise (bare coordinate list) every line with exactly 4 fields is taken as an atom.
sub read_xyz {
    my ($file) = @_;
    my @coords;
    open (my $fh, "<", $file) || die "Failed to open $file : $!";
    my @lines = <$fh>;
    close($fh);
    s/^\s+|\s+$//g for @lines;
    if (@lines && $lines[0] =~ /^\d+$/) {
        my $n = $lines[0];
        die "Error: $file announces $n atoms but has only ".(@lines-2)." coordinate lines.\n" if @lines < $n + 2;
        for my $l (@lines[2 .. $n+1]) {
            my @a = split(/\s+/, $l);
            die "Error: bad coordinate line in $file: '$l'\n" if @a < 4;
            push @coords, [@a[0..3]];
        }
    } else {
        for my $l (@lines) {
            my @a = split(/\s+/, $l);
            push @coords, [@a] if @a == 4;
        }
    }
    return @coords;
}

# Cell (3x3, rows a, b, c in Angstrom) of a CP2K input/restart, *-1.cell (last step) or POSCAR file,
# read with cp2k_inp.py (next to this script, else in PATH)
sub read_cp2k_cell {
    my ($file) = @_;
    my $exe;
    my $self_dir = dirname(abs_path($0));
    for my $dir ($self_dir, split(/:/, $ENV{PATH} // '')) {
        if (-x "$dir/cp2k_inp.py") { $exe = "$dir/cp2k_inp.py"; last; }
    }
    die "Error: cp2k_inp.py not found (keep it next to $0 or in PATH); it is needed for -c.\n" unless $exe;
    open(my $fh, '-|', $exe, 'get-cell', $file, '--format', 'vectors', '--fmt', '.17g')
        || die "Failed to run $exe: $!\n";
    my @cell = map { [split] } grep { /\S/ } <$fh>;
    close($fh);
    die "Error: could not read the cell from $file\n" if $? != 0 || @cell != 3;
    return @cell;
}

# Inverse of a 3x3 matrix
sub inverse3 {
    my ($m) = @_;
    my @a = @$m;
    my $det = $a[0][0]*($a[1][1]*$a[2][2]-$a[1][2]*$a[2][1])
            - $a[0][1]*($a[1][0]*$a[2][2]-$a[1][2]*$a[2][0])
            + $a[0][2]*($a[1][0]*$a[2][1]-$a[1][1]*$a[2][0]);
    die "Error: cell matrix is singular\n" if abs($det) < 1e-12;
    my @r;
    for my $p (0..2) { for my $q (0..2) {
        my @rows = grep { $_ != $q } 0..2;
        my @cols = grep { $_ != $p } 0..2;
        my $minor = $a[$rows[0]][$cols[0]]*$a[$rows[1]][$cols[1]] - $a[$rows[0]][$cols[1]]*$a[$rows[1]][$cols[0]];
        $r[$p][$q] = (($p + $q) % 2 ? -1 : 1) * $minor / $det;
    } }
    return @r;
}
