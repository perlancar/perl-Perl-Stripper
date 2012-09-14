package Perl::Stripper;

use 5.010;
use strict;
use warnings;
use Log::Any qw($log);

use PPI;
use Moo;

# VERSION

has maintain_linum      => (is => 'rw', default => sub { 1 });
has strip_comment       => (is => 'rw', default => sub { 1 });
has strip_pod           => (is => 'rw', default => sub { 1 });
has strip_ws            => (is => 'rw', default => sub { 1 });
has strip_log           => (is => 'rw', default => sub { 0 });
has stripped_log_levels => (is => 'rw', default => sub { [qw/debug trace/] });

sub _strip_el_content {
    my ($self, $el) = @_;

    my $ct;
    if ($self->maintain_linum) {
        $ct = $el->content;
        my $num_nl = () = $ct =~ /\R/g;
        $ct = "\n" x $num_nl;
    } else {
        $ct = "";
    }
    $el->set_content($ct);
}

sub _strip_node_content {
    my ($self, $node) = @_;

    my $ct;
    if ($self->maintain_linum) {
        $ct = $node->content;
        my $num_nl = () = $ct =~ /\R/g;
        $ct = "\n" x $num_nl;
    } else {
        $ct = "";
    }
    $node->prune(sub{1});
    $node->add_element(PPI::Token::Whitespace->new($ct)) if $ct;
}

sub strip {
    my ($self, $perl) = @_;

    my @ll   = @{ $self->stripped_log_levels };
    my @llf  = map {$_."f"} @ll;
    my @isll = map {"is_$_"} @ll;

    my $doc = PPI::Document->new(\$perl);
    my $res = $doc->find(
        sub {
            my ($top, $el) = @_;

            if ($self->strip_comment && $el->isa('PPI::Token::Comment')) {
                if (ref($self->strip_comment) eq 'CODE') {
                    $self->strip_comment->($el);
                } else {
                    $self->_strip_el_content($el);
                }
            }

            if ($self->strip_pod && $el->isa('PPI::Token::Pod')) {
                if (ref($self->strip_pod) eq 'CODE') {
                    $self->strip_pod->($el);
                } else {
                    $self->_strip_el_content($el);
                }
            }

            if ($self->strip_log) {
                my $match;
                if ($el->isa('PPI::Statement')) {
                    # matching '$log->trace(...);'
                    my $c0 = $el->child(0);
                    if ($c0->content eq '$log') {
                        my $c1 = $c0->snext_sibling;
                        if ($c1->content eq '->') {
                            my $c2 = $c1->snext_sibling;
                            my $c2c = $c2->content;
                            if ($c2c ~~ @ll || $c2c ~~ @llf) {
                                $match++;
                            }
                        }
                    }
                }
                if ($el->isa('PPI::Statement::Compound')) {
                    # matching 'if ($log->is_trace) { ... }'
                    my $c0 = $el->child(0);
                    if ($c0->content eq 'if') {
                        my $cond = $c0->snext_sibling;
                        if ($cond->isa('PPI::Structure::Condition')) {
                            my $expr = $cond->child(0);
                            if ($expr->isa('PPI::Statement::Expression')) {
                                my $c0 = $expr->child(0);
                                if ($c0->content eq '$log') {
                                    my $c1 = $c0->snext_sibling;
                                    if ($c1->content eq '->') {
                                        my $c2 = $c1->snext_sibling;
                                        my $c2c = $c2->content;
                                        if ($c2c ~~ @isll) {
                                            $match++;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if ($match) {
                    if (ref($self->strip_log) eq 'CODE') {
                        $self->strip_log->($el);
                    } else {
                        $self->_strip_node_content($el);
                    }
                }
            }

            0;
        }
    );
    die "BUG: find() dies: $@!" unless defined($res);

    $doc->serialize;
}

1;
#ABSTRACT: Yet another PPI-based Perl source code stripper

=head1 SYNOPSIS

 use Perl::Stripper;

 my $stripper = Perl::Stripper->new(
     #maintain_linum => 1, # the default, keep line numbers unchanged
     #strip_ws       => 1, # the default, strip extra whitespace
     #strip_comment  => 1, # the default
     #strip_pod      => 1, # the default
     strip_log       => 1, # default is 0, strip Log::Any log statements
 );
 $stripped = $stripper->strip($perl);


=head1 DESCRIPTION

This module is yet another PPI-based Perl source code stripper. Its focus is on
costumization. This module can be used to "hide" the source code (or to be more
exact, remove some meaningful parts of it, like comments and documentation) or
to obfuscate it to a degree.

This module uses L<Moo> object system.

This module uses L<Log::Any> logging framework.


=head1 ATTRIBUTES

=head2 maintain_linum => BOOL (default: 1)

If set to true, stripper will try to maintain line numbers so it does not change
between the unstripped and the stripped version. This is useful for debugging.

Respected by other settings.

=head2 strip_ws => BOOL (default: 1)

Strip extra whitespace. Under C<maintain_linum>, will not strip newlines.

Not yet implemented.

=head2 strip_comment => BOOL (default: 1) | CODE

If set to true, will strip comments. Under C<maintain_linum> will replace
comment lines with blank lines.

Can also be set to a coderef. Code will be given the PPI comment token object
and expected to modify the object (e.g. using C<set_content()> method). See
L<PPI::Token::Comment> for more details. Some usage ideas: translate comment,
replace comment with gibberish, etc.

=head2 strip_log => BOOL (default: 1)

If set to true, will strip log statements. Useful for removing debugging
information. Currently L<Log::Any>-specific and only looks for the default
logger C<$log>. These will be stripped:

 $log->METHOD(...);
 $log->METHODf(...);
 if ($log->is_METHOD) { ... }

Not all methods are stripped. See C<stripped_log_levels>.

Can also be set to a coderef. Code will be given the L<PPI::Statement> object
and expected to modify it.

=head2 stripped_log_levels => ARRAY_OF_STR (default: ['debug', 'trace'])

Log levels to strip. By default, only C<debug> and C<trace> are stripped. Levels
C<info> and up are considered important for users (instead of for developers
only).

=head2 strip_pod => BOOL (default: 1)

If set to true, will strip POD. Under C<maintain_linum> will replace POD with
blank lines.

Can also be set to a coderef. Code will be given the PPI POD token object and
expected to modify the object (e.g. using C<set_content()> method). See
L<PPI::Token::Pod> for more details.Some usage ideas: translate POD, convert POD
to Markdown, replace POD with gibberish, etc.


=head1 METHODS

=head2 new(%attrs) => OBJ

Constructor.

=head2 $stripper->strip($perl) => STR

Strip Perl source code. Return the stripped source code.


=head1 TODO/IDEAS

=over 4

=item * Don't strip shebang line

=item * Option to mangle subroutine names

With exclude and mangling options (dictionary, name mangler sub).

=item * Option to mangle name of lexical variables

With exclude and mangling options (dictionary, name mangler sub).

=item * Option to mangle name of global variables

With exclude and mangling options (dictionary, name mangler sub). And exclude
Perl's predefined variables like C<@ARGV>, C<%ENV>, and so on.

=item * Option to mangle labels

=item * Option to remove comments and whitespace in /x regexes

=back


=head1 FAQ


=head1 SEE ALSO

There are at least two approaches when analyzing/modifying/producing Perl code:
L<B>-based and L<PPI>-based. In general, B-based modules are orders of magnitude
faster than PPI-based ones, but each approach has its strengths and weaknesses.

L<B::Deparse> - strips comments and extra newlines

L<B::Deobfuscate> - like B::Deparse, but can also rename variables. Despite its
name, if applied to a "normal" Perl code, the effect is obfuscation because it
removes the original names (and meaning) of variables.

L<Perl::Strip> - PPI-based, focus on compression.

L<Perl::Squish> - PPI-based, focus on compression.

=cut
