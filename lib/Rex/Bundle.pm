#
# (c) Jan Gehring <jan.gehring@gmail.com>
# 
# vim: set ts=3 sw=3 tw=0:
# vim: set expandtab:

package Rex::Bundle;

use strict;
use warnings;

our $VERSION = '0.1';

require Exporter;
use base qw(Exporter);

use vars qw(@EXPORT $install_dir);
use LWP::Simple;
use Cwd qw(getcwd);

@EXPORT = qw(mod install_to);

# currently only supports $name
sub mod {
   my ($name, $version) = @_;
   
   my $mod_url = _lookup_module_url($name);
   _download($mod_url);
   my ($file_name) = $mod_url =~ m{/CPAN/authors/id/.*/(.*?\.(?:tar\.gz|tgz|tar\.bz2|zip))};
   my ($dir_name) = $mod_url =~ m{/CPAN/authors/id/.*/(.*?)\.(?:tar\.gz|tgz|tar\.bz2|zip)};

   my $rnd = _gen_rnd();
   my $new_dir = $dir_name . "-" . $rnd;

   _extract_file($file_name);
   _rename_dir($dir_name, $new_dir);
   _configure($new_dir);
   _make($new_dir);
   _test($new_dir);
   _install($new_dir);
}

sub install_to {
   $install_dir = shift;
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
   system("curl -L -O -# http://search.cpan.org$url");
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

   system(sprintf($cmd, $file));
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
   if(-f "Makefile.PL") {
      $cmd = "perl Makefile.PL PREFIX=$cwd/$install_dir INSTALLPRIVLIB=$cwd/$install_dir INSTALLSITELIB=$cwd/$install_dir INSTALLARCHLIB=$cwd/$install_dir INSTALLVENDORARCH=$cwd/$install_dir";
   } elsif(-f "Build.PL") {
      die("not supported yet!");
   } else {
      die("not supported");
   }

   system($cmd);
   die("Error $cmd") if($? != 0);
   chdir($cwd);
}

sub _make {
   my($dir) = @_;
   
   my $cwd = getcwd;
   chdir(_work_dir() . '/' . $dir);

   my $cmd;
   if(-f "Makefile.PL") {
      $cmd = "make";
   } elsif(-f "Build.PL") {
      die("not supported yet!");
   } else {
      die("not supported");
   }

   system($cmd);
   die("Error $cmd") if($? != 0);
   chdir($cwd);
}

sub _test {
   my($dir) = @_;
   
   my $cwd = getcwd;
   chdir(_work_dir() . '/' . $dir);

   my $cmd;
   if(-f "Makefile.PL") {
      $cmd = "make test";
   } elsif(-f "Build.PL") {
      die("not supported yet!");
   } else {
      die("not supported");
   }

   system($cmd);
   die("Error $cmd") if($? != 0);
   chdir($cwd);
}

sub _install {
   my($dir) = @_;
   
   my $cwd = getcwd;
   chdir(_work_dir() . '/' . $dir);

   my $cmd;
   if(-f "Makefile.PL") {
      $cmd = "make install";
   } elsif(-f "Build.PL") {
      die("not supported yet!");
   } else {
      die("not supported");
   }

   system($cmd);
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

if( ! -d _work_dir() ) {
   mkdir (_work_dir(), 0755);
}

srand;

1;
