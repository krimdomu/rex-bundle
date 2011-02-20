#
# (c) Jan Gehring <jan.gehring@gmail.com>
# 
# vim: set ts=3 sw=3 tw=0:
# vim: set expandtab:

package Rex::Bundle;

use strict;
use warnings;

our $VERSION = '0.2';

require Exporter;
use base qw(Exporter);

use vars qw(@EXPORT $install_dir $rex_file_dir);
use LWP::Simple;
use Cwd qw(getcwd);
use YAML;
use Data::Dumper;

@EXPORT = qw(mod install_to);

# currently only supports $name
sub mod {
   my $name = shift;
   my $opts = { @_ };
   
   $rex_file_dir = getcwd;

   if(!$install_dir) {
      print STDERR "You have to define install_to in your Rexfile\n";
      exit 1;
   }

   unless(exists $opts->{'force'}) {
      eval { my $m = $name; $m =~ s{::}{/}g; require "$m.pm"; }; 
      if(! $@) {
         print STDERR "$name is already installed.\n";
         return;
      }
   }

   my $rnd = _gen_rnd();

   my($file_name, $dir_name, $new_dir);
   if(defined $opts->{'url'}) {
      $new_dir = $name;
      $new_dir =~ s{::}{-}g;
      $new_dir .= "-$rnd";
      _clone_repo($opts->{'url'}, $new_dir);
   } else {
      my $mod_url = _lookup_module_url($name);
      _download($mod_url);

      ($file_name) = $mod_url =~ m{/CPAN/authors/id/.*/(.*?\.(?:tar\.gz|tgz|tar\.bz2|zip))};
      ($dir_name) = $mod_url =~ m{/CPAN/authors/id/.*/(.*?)\.(?:tar\.gz|tgz|tar\.bz2|zip)};
      $new_dir = $dir_name . "-" . $rnd;

      _extract_file($file_name);
      _rename_dir($dir_name, $new_dir);
   }

   { local $_; mod($_) for _get_deps($new_dir); }

   _configure($new_dir);
   _make($new_dir);
   _test($new_dir);
   _install($new_dir);
}

sub install_to {
   $install_dir = shift;
   lib->import(getcwd . '/' . $install_dir);
   $ENV{'PATH'} = $install_dir . '/bin:' . $ENV{'PATH'};
   $ENV{'PERL5LIB'} = $install_dir . ':' . ( $ENV{'PERL5LIB'} || '' );
   $ENV{'PERLLIB'} = $install_dir . ':' . ( $ENV{'PERLLIB'} || '' );
}

# private functions
sub _lookup_module_url {
   my ($name, $version) = @_;
   my $url = 'http://search.cpan.org/perldoc?' . $name;
   my $html = get($url);
   my ($dl_url) = $html =~ m{<a href="(/CPAN/authors/id/.*?\.(?:tar\.gz|tgz|tar\.bz2|zip))">};
   if($dl_url) {
      return $dl_url;
   } else {
      die("module not found ($url).");
   }
}

sub _download {
   my ($url) = @_;

   my $cwd = getcwd;
   chdir(_work_dir());
   _call("curl -L -O -# http://search.cpan.org$url");
   chdir($cwd);
}

sub _extract_file {
   my($file) = @_;

   my $cwd = getcwd;
   chdir(_work_dir());

   my $cmd;
   if($file =~ m/\.tar\.gz$/) {
      $cmd = 'tar -xvzf %s';
   } elsif($file =~ m/\.tar\.bz2/) {
      $cmd = 'tar -xjvf %s';
   }

   _call(sprintf($cmd, $file));
   chdir($cwd);
}

sub _rename_dir {
   my($old, $new) = @_;
   
   my $cwd = getcwd;
   chdir(_work_dir());

   rename($old, $new);

   chdir($cwd);
}

sub _configure {
   my($dir) = @_;

   my $cwd = getcwd;
   chdir(_work_dir() . '/' . $dir);

   my $cmd;
   if(-f "Build.PL") {
      $cmd = 'perl Build.PL';
   } elsif(-f "Makefile.PL") {
      $cmd = "perl Makefile.PL PREFIX=$cwd/$install_dir INSTALLPRIVLIB=$cwd/$install_dir INSTALLSITELIB=$cwd/$install_dir INSTALLARCHLIB=$cwd/$install_dir INSTALLVENDORARCH=$cwd/$install_dir";
   } else {
      die("not supported");
   }

   _call($cmd);
   die("Error $cmd") if($? != 0);
   chdir($cwd);
}

sub _make {
   my($dir) = @_;
   
   my $cwd = getcwd;
   chdir(_work_dir() . '/' . $dir);

   my $cmd;
   if(-f "Build") {
      $cmd = './Build';
   } elsif(-f "Makefile") {
      $cmd = "make";
   } else {
      die("not supported");
   }

   _call($cmd);
   die("Error $cmd") if($? != 0);
   chdir($cwd);
}

sub _test {
   my($dir) = @_;
   
   my $cwd = getcwd;
   chdir(_work_dir() . '/' . $dir);

   my $cmd;
   if(-f "Build") {
      $cmd = "./Build test";
   } elsif(-f "Makefile") {
      $cmd = "make test";
   } else {
      die("not supported");
   }

   _call($cmd);
   die("Error $cmd") if($? != 0);
   chdir($cwd);
}

sub _install {
   my($dir) = @_;
   
   my $cwd = getcwd;
   chdir(_work_dir() . '/' . $dir);

   my $cmd;
   if(-f "Build") {
      $cmd = "./Build install --install_path lib=$cwd/$install_dir --install_path arch=$cwd/$install_dir --install_path script=$cwd/$install_dir/bin --install_path bin=$cwd/$install_dir/bin --install_path bindoc=$cwd/$install_dir/man --install_path libdoc=$cwd/$install_dir/man --install_path libhtml=$cwd/$install_dir/html --install_path binhtml=$cwd/$install_dir/html";
   } elsif(-f "Makefile") {
      $cmd = "make install";
   } else {
      die("not supported");
   }

   _call($cmd);
   die("Error $cmd") if($? != 0);
   chdir($cwd);
}

sub _gen_rnd {
   my @chars = qw(a b c d e f g h i j k l m n o p u q s t u v w x y z 0 1 2 3 4 5 6 7 8 9);
   my $ret = '';

   for (0..4) {
      $ret .= $chars[int(rand(scalar(@chars)))];
   }

   $ret;
}

sub _work_dir {
   return $ENV{'HOME'} . '/.rexbundle';
}

sub _get_deps {
   my ($dir) = @_;

   
   my $cwd = getcwd;
   chdir(_work_dir() . '/' . $dir);
   my @ret;

   my $found=0;

   if(-f 'META.yml') {
      my $yaml = eval { local(@ARGV, $/) = ('META.yml'); $_=<>; $_; };
      eval {
         my $struct = Load($yaml);
         push(@ret, keys %{$struct->{'configure_requires'}});
         push(@ret, keys %{$struct->{'build_requires'}});
         push(@ret, keys %{$struct->{'requires'}});
         $found=1;
      };

      if($@) {
         print STDERR "Error parseing META.yml :(\n";
         # fallback and try Makefile.PL
      }
   } else {
      # no meta.yml found :(
      print STDERR "No META.yml found :(\n";
      @ret = ();
   }

   if(!$found) {
      if(-f "Makefile.PL") {
         no strict;
         no warnings 'all';
         my $makefile = eval { local(@ARGV, $/) = ("Makefile.PL"); <>; };
         my ($hash_string) = ($makefile =~ m/WriteMakefile\((.*?)\);/ms);
         my $make_hash = eval "{$hash_string}";
         if(exists $make_hash->{"PREREQ_PM"}) {
            for my $mod (keys %{$make_hash->{"PREREQ_PM"}}) {
               push(@ret, $mod);
            }
         }
         use strict;
         use warnings;
      }
   }

   chdir($cwd);

   my @needed = grep { ! /^perl$/ } grep { ! eval { my $m = $_; $m =~ s{::}{/}g; require "$m.pm"; 1;} } @ret;
   print "Found following dependencies: \n";
   print Dumper(\@needed);

   @needed;
}

sub _clone_repo {
   my($repo, $path) = @_;

   my $cmd = "%s %s %s %s";
   my @p = ();

   if($repo =~ m/^git/) {
      @p = qw(git clone);
      push @p, $repo, $path;
   } elsif($repo =~ m/^svn/) {
      @p = qw(svn export);
      push @p, $repo, $path;
   } else {
      die("Repositoryformat not supported: $repo");
   }

   my $cwd = getcwd;
   chdir(_work_dir());

   _call(sprintf($cmd, @p));

   chdir($cwd);
}

sub _call {
   my ($cmd) = @_;

   $ENV{'PERL5LIB'} .= ":$rex_file_dir/$install_dir";
   $ENV{'PERLLIB'} .= ":$rex_file_dir/$install_dir";
   system($cmd);
}

if( ! -d _work_dir() ) {
   mkdir (_work_dir(), 0755);
}

srand;

1;
