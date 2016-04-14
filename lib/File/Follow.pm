package File::Follow;

use 5.0006;
use strict;
use vars qw($VERSION);

=head1 NAME

File::Follow - A log file follower, with log rotation detection

=head1 VERSION

Version 0.2

=cut

our $VERSION = '0.2';

=head1 SYNOPSIS

  use File::Follow;

  sub myLineCallback {
    print "Got a line: $_[1]";
  }

  File::Follow::new('/var/log/system.log',
                    SkipToEnd => 1,
                    LineCallback => \&myLineCallback);

=head1 CONSTRUCTOR

=over 4

=item new( FILENAME [, OPTIONS ] )

Create a new C<File::Follow> object.  In truth, this is the only method in the
entire class.  Everything else is handled through user-defined callbacks.

C<FILENAME> is the name of the file to follow.

C<OPTIONS> is a hash, containing zero or more of the following keys:

=over 4

B<SkipToEnd> - If nonzero, the module will skip to the end of C<FILENAME>
after opening it for the first time.  This gives the equivalent to the
C<tail -0f> command.

B<LineCallback> - Subroutine called after each line is read.  The subroutine
will receive two parameters: this C<File::Follow> object, and the line that was
read from the file, B<including> any end-of-line characters.  If this is not
specified, then a default callback, which just prints each line read, like
the C<tail -f> command, will be used.  To defeat this, either provide a
pointer to your own callback function, or pass C<undef>.

B<FileOpenCallback> - Subroutine called B<after> each file is opened,
including the initial open of the file, followed by subsequent opens as a
result of log rotation.  The subroutine will receive this C<File::Follow> object
as its sole parameter.

B<FileCloseCallback> - Subroutine called B<before> each file is closed
(for example, when the module determines that the log has been rotated).
The subroutine will receive this C<File::Follow> object as its sole parameter.

B<PeriodicCallback> - Subroutine called B<after> the contents of the file
(at the moment) have been exhausted.  The subroutine will receive this
C<File::Follow> object as its sole parameter.

B<StateFile> - Pathname to a file that will retain the state of this
C<File::Follow> object.  This allows a subsequent run to pick up where it
left off.

=back

=back

=head1 OBJECT FIELDS

Within the C<File::Follow> hash, the following fields are of interest:

=over 4

B<fh> - A handle to the file just opened, or just about to be closed.
This may be manipulated by the callback (calling seek, getting
additional lines, etc.), and will cause File::Follow to continue from
the new position in the log file.

B<finishNow> - If set to 1 in a callback, then the File::Follow object
will be closed and destroyed.

=back

=cut

sub _doCallback($$;$) {
    my ($self, $cb, $param) = @_;
    if (defined $self->{$cb}) {
	if (defined $param) {
	    &{$self->{$cb}}($self, $param);
	}
	else {
	    &{$self->{$cb}}($self);
	}
    }
}

sub new($;%) {
    shift @_ if $_[0] eq 'File::Follow';
    my ($filename, %options) = @_;
    my $self = {};
    bless $self;
    $self->{'filename'} = $filename;
    $self->{'linecallback'} = sub { print $_[1]; };
    foreach('LineCallback', 'FileOpenCallback', 'FileCloseCallback', 'SkipToEnd', 'StateFile', 'PeriodicCallback') {
	$self->{lc $_} = $options{$_} if defined $options{$_};
    }
    $self->{'inum'} = (stat $self->{'filename'})[1];
    $self->{'finishNow'} = 0;
    my $lastTime;
    while (!$self->{'finishNow'}) {
	unless ($self->{'fh'}) {
	    open($self->{'fh'}, $self->{'filename'}) or die 'Cannot open '.$self->{'filename'}.": $!";
	    if ($self->{'statefile'} && -f $self->{'statefile'}) {
		open my $sfh, '<', $self->{'statefile'};
		my $state = <$sfh>;
		close $sfh;
		if ($state) {
		    my ($dev, $ino, $pos) = split(' ', $state);
		    my ($fhdev, $fhino) = stat $self->{'fh'};
		    seek $self->{'fh'}, $pos, 0 if ($dev == $fhdev) && ($ino == $fhino);
		}
	    }
	    else {
		seek $self->{'fh'}, 0, 2 if $self->{'skiptoend'};
	    }
	    undef $self->{'skiptoend'};
	    _doCallback($self, 'fileopencallback');
	    last if $self->{'finishNow'};
	}
	my $fh = $self->{'fh'};
	while (<$fh>) {
	    _doCallback($self, 'linecallback', $_);
	    if ($self->{'statefile'}) {
		open my $sfh, '>', $self->{'statefile'};
		print $sfh join(' ', (stat $fh)[0,1], tell $fh);
		close $sfh;
	    }
	    last if $self->{'finishNow'};
	}
	_doCallback($self, 'periodiccallback');
	if ($lastTime || $self->{'finishNow'}) {
	    _doCallback($self, 'fileclosecallback');
	    close($self->{'fh'});
	    undef $self->{'fh'};
	    next;
	}
	if ($self->{'inum'} != (stat $self->{'filename'})[1]) {
	    $lastTime = 1;
	    next;
	}
	sleep 1;
    }
    if ($self->{'fh'}) {
	close($self->{'fh'}); 
	_doCallback($self, 'fileclosecallback');
    }
}

=head1 AUTHOR

Dj Padzensky <padzensky@apple.com>

=cut
1;
