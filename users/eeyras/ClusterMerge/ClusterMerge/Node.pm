#
# Written by Eduardo Eyras
#
# Copyright GRL & EBI
#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code=pod 

=head1 NAME

ClusterMerge::Node;

=head1 SYNOPSIS

    my $node = ClusterMerge::Node->new();
						 


    my $is_extended = $node->is_extended;

    etc...

=head1 DESCRIPTION

An object of type node presents a node in a ClusterMerge tree.
It can have one extension parent, several extension children and one inclusion
tree attached to it, which is represented by the leaves of that sub-tree.
It also holds all the inclusion children from the first generation.

=head1 CONTACT

eae@sanger.ac.uk

=head1 APPENDIX

The rest of the documentation details each of the object methods. 
Internal methods are usually preceded with a _

=head1 AUTHOR

eae@sanger.ac.uk

=cut

package ClusterMerge::Node;

use ClusterMerge::Root;
use vars qw(@ISA);
use strict;

@ISA = qw(ClusterMerge::Root);

sub new {
  my ($class,@args) = @_;
  my $self = $class->SUPER::new(@args);
  
  my( $extension_parent, $inclusion_parent, $inclusion_children ) = 
    $self->_rearrange([qw(
			  EXTENSION_PARENT
			  INCLUSION_PARENT
			  INCLUSION_CHILDREN
			 )], 
		      @args);
  
  if( $extension_parent ){
    $self->extension_parent($extension_parent);
  }

  if ( $inclusion_parent ){
    $self->inclusion_parent($inclusion_parent);
  }

  if ($inclusion_children){
    $self->inclusion_children($inclusion_children);
  }
  
  return $self;
}


############################################################

# a tree is an arrayref containing the leaves (which are Node objects)
# the inclusion tree from a node is obtained

=head2 inclusion_tree

 Function: returns the inclusion tree attached to a given node: the set of leaves 
    of the sub tree by inclusion. It is calculated by getting the first 
    generation and obtaining the nodes which are not extended. If we remove the 
    inclusion links from this node, these would be the nodes that are not 
    extended nor included in any other node, which 
    is our definition of leaf. We return undef when there are no inclusion-children or 
    when a leaf could not be found, which happens when there is a leaf of the global 
    tree attached to the sub-tree.
  Note: this method will not distinguish between not having an inclusion tree at all and 
    having a not-valid inclusion tree. Thus to check whether there is an inclusion 
    tree but it is not valid we must do: 
    if ( $node->inclusion_children && !$node->inclusion_tree )
          
=cut
  
sub inclusion_tree{
  my ($self) = @_; 
  my @leaves;
  if ( @{$self->inclusion_children} ){
    
    foreach my $node (  @{$self->inclusion_children} ){
      if( $node->is_extended ){ 
	#print STDERR "not putting node ".$node->transcript->dbID." in the inclusion tree\n";
      }
      else{
	push( @leaves, $node );
      }
    }
  }
  else{
    return undef;
  }
  
  if (@leaves){
    return \@leaves;
  }
  else{
    return undef;
  }
}

############################################################
#
# GET/SET METHODS
#
############################################################

sub collected{
  my ($self, $boolean ) = @_;
  if ( $boolean ){
    $self->{_collected} = $boolean;
  }
  return $self->{_collected};
}

############################################################

sub is_extended{
  my ($self, $boolean ) = @_;
  if ( $boolean ){
    $self->{_is_extended} = $boolean;
  }
  return $self->{_is_extended};
}
############################################################

sub is_included{
  my ($self, $boolean ) = @_;
  if ( $boolean ){
    $self->{_is_included} = $boolean;
  }
  return $self->{_is_included};
}

############################################################

=head2 extension_parents

Function: returns an arrayref with all the extension parents (Node objects) of this node.

=cut

sub extension_parents{
  my ($self) = @_;
  unless( $self->{_extension_parents} ){
    $self->{_extension_parents} = [];
  }
  return $self->{_extension_parents};
}
############################################################

sub add_extension_parent{
    my ($self,$node) = @_;
    unless( $self->{_extension_parents} ){
      $self->{_extension_parents} = [];
    }
    if ($node){
      push ( @{$self->{_extension_parents}}, $node );
    }
    return $self->{_extension_parents};
}
############################################################

sub inclusion_parents{
  my ($self) = @_;
  unless( $self->{_inclusion_parents} ){
    $self->{_inclusion_parents} = [];
  }
  return $self->{_inclusion_parents};
}

############################################################

sub add_inclusion_parent{
    my ($self,$node) = @_;
    unless( $self->{_inclusion_parents} ){
      $self->{_inclusion_parents} = [];
    }
    if ($node){
      push ( @{$self->{_inclusion_parents}}, $node );
    }
    return $self->{_inclusion_parents};
}
############################################################

sub add_extension_child{
    my ($self,$node) = @_;
    unless( $self->{_extension_children} ){
      $self->{_extension_children} = [];
    }
    if ($node){
      push ( @{$self->{_extension_children}}, $node );
    }
    return $self->{_extension_children};
}
############################################################

sub extension_children{
  my ($self) = @_;
  unless ( $self->{_extension_children} ){
    $self->{_extension_children} = [];
  }
  return $self->{_extension_children};
}

############################################################

sub add_inclusion_child{
    my ($self,$node) = @_;
    unless ( $self->{_inclusion_children} ){
	$self->{_inclusion_children} = [];
    }
    if ( $node ){
	push( @{$self->{_inclusion_children}}, $node);
    }
    return $self->{_inclusion_children};
}

############################################################

# a generation is an arrayref of Node objects
sub inclusion_children{
  my ($self) = @_;
  unless ( $self->{_inclusion_children} ){
    $self->{_inclusion_children} = [];
  }
  return $self->{_inclusion_children};
}
############################################################

# each node will contain an element in the form of a transcript object:
sub transcript{
    my ($self, $t) = @_;
    if ($t && $self->{_transcript}){
	$self->warn("resetting the transcript of a node. Are you sure this is right?");
	$self->{_transcript} = $t;
    }
    elsif ($t){
	$self->{_transcript} = $t;
    }
    return $self->{_transcript};
}

############################################################

sub candidate_extension_parents{
  my ($self) = @_;
  unless( $self->{_candidate_extension_parents} ){
    $self->{_candidate_extension_parents} = [];
  }
  return $self->{_candidate_extension_parents};
}
############################################################

sub add_candidate_extension_parent{
    my ($self,$node) = @_;
    unless( $self->{_candidate_extension_parents} ){
      $self->{_candidate_extension_parents} = [];
    }
    if ($node){
      push ( @{$self->{_candidate_extension_parents}}, $node );
    }
    return $self->{_candidate_extension_parents};
}
############################################################

sub is_candidate{
  my ($self, $boolean ) = @_;
  if ( $boolean ){
    $self->{_is_candidate} = $boolean;
  }
  return $self->{_is_candidate};
}

1;





























































