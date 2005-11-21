# $Id: UtilsServices.pm,v 1.15 2005-11-21 13:30:02 gmaster Exp $
#
# This file is an instance of a template written 
# by Roman Roset, INB (Instituto Nacional de Bioinformatica), Spain.
#
# POD documentation - main docs before the code


=head1 NAME

INB::GRIB::Services::UtilsServices  - Package for auxialiary services such as translating a set of GeneID predicitions or converting blast output into GeneID evidences GFFF format.

=head1 SYNOPSIS

Con este package podremos parsear las llamadas xml de BioMoby para
poder llamar al servicio runGeneid. Una vez que tengamos la salida de llamando
a las funciones de Factory.pm, podremos encapsularla a objectos BioMoby.

  # Esta llamada/s nos devuelve una variable que contiene el texto con la
  # salida del programa Geneid encapsulado en objetos Moby. 

=head1 DESCRIPTION

Este package sirve para parsear las llamadas BioMoby de entrada y salida.  
De esta forma hace de puente entre el cliente que llama el servicio y la 
aplicacion geneid.

Tipicamente la libreria que necesitamos en este m�dulo es la MOBY::CommonSubs,
que podremos ver tecleando en el terminal:
> perldoc MOBY::CommonSubs

No obstante, en esta libreria puede que no encontremos todo lo que necesitamos.
Si es as� tendiamos que utilizar un parser de XML y una libreria que lo
interprete. Estas librerias podrian ser:

use XML::DOM;
use XML::Parser

y hacer cosas como:

my $parser = new XML::DOM::Parser;
my $doc = $parser->parse($message);
my $nodes = $doc->getElementsByTagName ("moby:Simple");
my $xml   = $nodes->item(0)->getFirstChild->toString;

Atencion: recomiendo mirarse esta libreria, solo cuando CommonSubs no nos de
nuestra solucion. La raz�n de ello es que, si cambia el estandard bioMoby, en
principio las llamadas a CommonSubs no tendr�an que cambiar, pero si no las 
hacemos servir, puede que debamos modificar el c�digo.


=head1 AUTHOR

Arnaud Kerhornou, akerhornou@imim.es

=head1 COPYRIGHT

Copyright (c) 2005, Arnaud Kerhornou and INB - Nodo 1 - GRIB/IMIM.
 All Rights Reserved.

This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.


=head1 DISCLAIMER

This software is provided "as is" without warranty of any kind.

=head1 APPENDIX

The rest of the documentation details each of the object
methods. Internal methods are usually preceded with a _

=cut

# Let the code begin...

package INB::GRIB::Services::UtilsServices;

use strict;
use warnings;
use Carp;

use INB::GRIB::Services::Factory;
use INB::GRIB::Utils::CommonUtilsSubs;
use MOBY::CommonSubs qw(:all);

use Data::Dumper;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use INB::UPC::Blast ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw() ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

# Aqui pondremos las funciones que reciben el mensaje BioMoby. Ejemplo 
# 
# @EXPORT = qw( &func1 &func2);
# 
our @EXPORT = qw(
  &translateGeneIDGFFPredictions
  &fromGenericSequencetoFASTA
  &fromGenericSequenceCollectiontoFASTA
  &fromFASTAtoDNASequenceCollection
  &generateScoreMatrix
);

our $VERSION = '1.0';

my $_debug = 0;

# Preloaded methods go here.

###############################################################################

=head2 _do_query_TranslateGeneIDGFF

 Title   : _do_query_TranslateGeneIDGFF
         : 
         : private function (NOT EXPORTED)
         : 
 Usage   : my $query_response = _do_query_GeneID($query);
         : 
         : donde:
         :   $query es un XML::DOM::Node que contiene el arbol xml que
         :   engloba:  
         :     <moby:mobyData queryID='1'>...</moby:mobyData>
         : 
 Returns : Devuelve un string que contiene el resultado de la ejecuci�n
         : para una sola query.
         : Un ejemplo ser�a: 
         : 
         : <moby:mobyData moby:queryID='1'>
         :   <moby:Simple moby:articleName='report'>
         :     <moby:text-plain namespace='Global_Keyword' id=''>
	 :    ....
         :     </moby:text-plain>
         :   </moby:Simple>
         : </moby:mobyData>

=cut

sub _do_query_TranslateGeneIDGFF {
    # $queryInput_DOM es un objeto DOM::Node con la informacion de una query biomoby 
    my $queryInput_DOM = shift @_;
    
    my $MOBY_RESPONSE = "";     # set empty response

    # Aqui escribimos las variables que necesitamos para la funcion. 
    my $translation_table = "Standard (1)";

    # Variables that will be passed to GeneID_call
    my %sequences;
    my %predictions;
    my %parameters;

    my $queryID  = getInputID ($queryInput_DOM);
    my @articles = getArticles($queryInput_DOM);

    # Get the parameters
    
    ($translation_table) = getNodeContentWithArticle($queryInput_DOM, "Parameter", "translation table");

    if ($_debug) {
	if (defined $translation_table) {
	    print STDERR "parsed translation table, $translation_table\n";
	}
	else {
	    print STDERR "no translation table parameter\n";
	}
    }

    if (not defined $translation_table) {
	# Default is the eukaryotic translation table
	$translation_table = "Standard (1)";
    }
    
    # Add the parsed parameters in a hash table
    
    if ($_debug) {
	print STDERR "translation table, $translation_table\n";
    }

    $parameters{translation_table} = $translation_table;
    
    # Tratamos a cada uno de los articulos
    foreach my $article (@articles) {       
	
	# El articulo es una tupla que contiene el nombre de este 
	# y su texto xml. 
	
	my ($articleName, $DOM) = @{$article}; # get the named article

	if ($_debug) {
	    print STDERR "processing article, $articleName...\n";
	}
	
	# Si le hemos puesto nombre a los articulos del servicio,  
	# podemos recoger a traves de estos nombres el valor.
	# Sino sabemos que es el input articulo porque es un simple/collection articulo

	# It's not very nice but taverna doesn't set up easily article name for input data so we let the users not setting up the article name of the input (which should be 'sequences')
	# In case of GeneID, it doesn't really matter as there is only one input anyway
	
	if ($articleName eq "sequences") { 
	    
	    if (isSimpleArticle ($DOM)) {

		if ($_debug) {
		    print STDERR "\"sequences\" tag is a simple article...\n";
		}

                %sequences = INB::GRIB::Utils::CommonUtilsSubs->parseMobySequenceObjectFromDOM ($DOM, \%sequences);

	    }
	    elsif (isCollectionArticle ($DOM)) {

		if ($_debug) {
		    print STDERR "sequences is a collection article...\n";
		    # print STDERR "Collection DOM: " . $DOM->toString() . "\n";
		}

		my @sequence_articles_DOM = getCollectedSimples ($DOM);
		
		foreach my $sequence_article_DOM (@sequence_articles_DOM) {
		    %sequences = INB::GRIB::Utils::CommonUtilsSubs->parseMobySequenceObjectFromDOM ($sequence_article_DOM, \%sequences);
		}
		
	    }
	    else {
		print STDERR "It is not a simple or collection article...\n";
		print STDERR "DOM: " . $DOM->toString() . "\n";
	    }
	} # End parsing sequences article tag
	
	if ($articleName eq "geneid_predictions") {
	    
	    if (isSimpleArticle ($DOM)) {
		
		if ($_debug) {
		    print STDERR "\"geneid_predictions\" tag is a simple article...\n";
		    print STDERR "node ref, " . ref ($DOM) . "\n";
		    print STDERR "DOM: " . $DOM->toString () . "\n";
		}
		
		my ($sequenceIdentifier) = getSimpleArticleIDs ( [ $DOM ] );
		
		if ((not defined $sequenceIdentifier) || (length ($sequenceIdentifier) == 0)) {
		    print STDERR "Error, can not parsed the sequence identifier the GFF is attach to!\n";
		    exit 0;
		}
		
		if ($_debug) {
		    print STDERR "parsed the following sequence identifier, $sequenceIdentifier\n";
		}
		
		my $prediction = INB::GRIB::Utils::CommonUtilsSubs->getTextContentFromXML ($DOM, "GFF");
		
		if ($_debug) {
		    print STDERR "prediction, $prediction\n";
		}

		# Add the predictions data into a hash table
		
		$predictions{$sequenceIdentifier} = $prediction;
	    }
	    elsif (isCollectionArticle ($DOM)) {
		
		if ($_debug) {
		    print STDERR "article, geneid_predictions, is a collection article...\n";
		    # print STDERR "Collection DOM: " . $DOM->toString() . "\n";
		}

		my @prediction_articles_DOM = getCollectedSimples ($DOM);
		
		foreach my $prediction_article_DOM (@prediction_articles_DOM) {
		    
		    if ($_debug) {
			print STDERR "node ref, " . ref ($prediction_article_DOM) . "\n";
			print STDERR "DOM: " . $prediction_article_DOM->toString () . "\n";
		    }
		    
		    my ($sequenceIdentifier) = getSimpleArticleIDs ( [ $prediction_article_DOM ] );

		    if ((not defined $sequenceIdentifier) || (length ($sequenceIdentifier) == 0)) {
			print STDERR "Error, can not parsed the sequence identifier the GFF is attach to!\n";
			exit 0;
		    }
		    
		    if ($_debug) {
			print STDERR "parsed the following sequence identifier, $sequenceIdentifier\n";
		    }
		    
		    my $prediction = INB::GRIB::Utils::CommonUtilsSubs->getTextContentFromXML ($DOM, "GFF");
		    
		    if ($_debug) {
			print STDERR "prediction, $prediction\n";
		    }
		    
		    # Add the predictions data into a hash table
		    
		    $predictions{$sequenceIdentifier} = $prediction;

		}
		
	    }
	    else {
		print STDERR "It is not a simple or collection article...\n";
		print STDERR "DOM: " . $DOM->toString() . "\n";
	    }
	} # End parsing predictionss article tag

    } # Next article
    
    # Check that we have parsed properly the sequences and the predictions
    
    if ((keys (%sequences)) == 0) {
	print STDERR "Error, can't parsed any sequences...\n";
    }
    if ((keys (%predictions)) == 0) {
	print STDERR "Error, can't parsed any predictions...\n";
    }
    
    # Una vez recogido todos los parametros necesarios, llamamos a 
    # la funcion que nos devuelve el report. 	
    
    my $fasta_sequences = TranslateGeneIDPredictions_call (sequences  => \%sequences, predictions  => \%predictions, parameters => \%parameters);
    
    # Ahora que tenemos la salida en el formato de la aplicacion XXXXXXX 
    # nos queda encapsularla en un Objeto bioMoby. Esta operacio 
    # la podriamos realizar en una funcion a parte si fuese compleja.  
    
    my $output_object_type  = "AminoAcidSequence";
    my $output_article_name = "peptides";
    my $namespace = "";

    if (not defined $fasta_sequences) {
	# Return an emtpy message !
	return collectionResponse (undef, $output_article_name, $queryID);
    
}
    my $aminoacid_objects   = INB::GRIB::Utils::CommonUtilsSubs->createSequenceObjectsFromFASTA ($fasta_sequences, $output_object_type, $namespace);

    # Bien!!! ya tenemos el objeto de salida del servicio , solo nos queda
    # volver a encapsularlo en un objeto biomoby de respuesta. Pero 
    # en este caso disponemos de una funcion que lo realiza. Si tuvieramos 
    # una respuesta compleja (de verdad, esta era simple ;) llamariamos 
    # a collection response. 
    # IMPORTANTE: el identificador de la respuesta ($queryID) debe ser 
    # el mismo que el de la query. 

    $MOBY_RESPONSE .= collectionResponse($aminoacid_objects, $output_article_name, $queryID);
	
    return $MOBY_RESPONSE;
}

=head2 _do_query_fromGenericSequencestoFASTA

 Title   : _do_query_fromGenericSequencestoFASTA
         : 
         : private function (NOT EXPORTED)
         : 
 Usage   : my $query_response = _do_query_GeneID($query);
         : 
         : donde:
         :   $query es un XML::DOM::Node que contiene el arbol xml que
         :   engloba:  
         :     <moby:mobyData queryID='1'>...</moby:mobyData>
         : 
 Returns : Devuelve un string que contiene el resultado de la ejecuci�n
         : para una sola query.
         : Un ejemplo ser�a: 
         : 
         : <moby:mobyData moby:queryID='1'>
         :   <moby:Simple moby:articleName='report'>
         :     <moby:text-plain namespace='Global_Keyword' id=''>
	 :    ....
         :     </moby:text-plain>
         :   </moby:Simple>
         : </moby:mobyData>

=cut

sub _do_query_fromGenericSequencestoFASTA {
    # $queryInput_DOM es un objeto DOM::Node con la informacion de una query biomoby 
    my $queryInput_DOM = shift @_;
    
    my $MOBY_RESPONSE = "";     # set empty response
    
    my $seqobjs = [];
    
    my $queryID  = getInputID ($queryInput_DOM);
    my @articles = getArticles($queryInput_DOM);
    
    # Tratamos a cada uno de los articulos
    foreach my $article (@articles) {       
	
	# El articulo es una tupla que contiene el nombre de este 
	# y su texto xml. 
	
	my ($articleName, $DOM) = @{$article}; # get the named article

	if ($_debug) {
	    print STDERR "processing article, $articleName...\n";
	}
	
	# Si le hemos puesto nombre a los articulos del servicio,  
	# podemos recoger a traves de estos nombres el valor.
	# Sino sabemos que es el input articulo porque es un simple/collection articulo

	# It's not very nice but taverna doesn't set up easily article name for input data so we let the users not setting up the article name of the input (which should be 'sequences')
	# In case of GeneID, it doesn't really matter as there is only one input anyway
	
	if (($articleName eq "sequences") || (isSimpleArticle ($DOM) || (isCollectionArticle ($DOM)))) { 
	    
	    if (isSimpleArticle ($DOM)) {
		
		if ($_debug) {
		    print STDERR "\"sequences\" tag is a simple article...\n";
		}
		
                my $seqobj = INB::GRIB::Utils::CommonUtilsSubs->parseMobySequenceObjectFromDOMintoBioperlObject ($DOM);
		push (@$seqobjs, $seqobj);
		
	    }
	    elsif (isCollectionArticle ($DOM)) {
		
		if ($_debug) {
		    print STDERR "sequences is a collection article...\n";
		    # print STDERR "Collection DOM: " . $DOM->toString() . "\n";
		}
		
		my @sequence_articles_DOM = getCollectedSimples ($DOM);
		
		foreach my $sequence_article_DOM (@sequence_articles_DOM) {
		    my $seqobj = INB::GRIB::Utils::CommonUtilsSubs->parseMobySequenceObjectFromDOMintoBioperlObject ($sequence_article_DOM);
		    push (@$seqobjs, $seqobj);
		}
		
	    }
	    else {
		print STDERR "It is not a simple or collection article...\n";
		print STDERR "DOM: " . $DOM->toString() . "\n";
	    }
	} # End parsing sequences article tag
	
    } # Next article
    
    # Check that we have parsed properly the sequences and the predictions
    
    if (@$seqobjs == 0) {
	print STDERR "Error, can't parsed any sequences...\n";
    }
    
    # Una vez recogido todos los parametros necesarios, llamamos a 
    # la funcion que nos devuelve el report. 	
    
    my $fasta_sequences = convertSequencesIntoFASTA ($seqobjs);
    
    # Ahora que tenemos la salida en el formato de la aplicacion XXXXXXX 
    # nos queda encapsularla en un Objeto bioMoby. Esta operacio 
    # la podriamos realizar en una funcion a parte si fuese compleja.  
    
    my $moby_output_format  = "FASTA";
    my $output_article_name = "sequences";
    my $namespace = "";

    my $sequenceIdentifier = "";
    # Specify the sequence identifier only in case there is only one sequence in the FASTA output
    if (@$seqobjs == 1) {
	my $seqobj = $seqobjs->[0];
	$sequenceIdentifier = $seqobjs->[0]->display_id;
    }
    
    my $fasta_object = <<PRT;
<moby:$moby_output_format namespace='' id='$sequenceIdentifier'>
<![CDATA[
$fasta_sequences
]]>
</moby:$moby_output_format>
PRT

    # Bien!!! ya tenemos el objeto de salida del servicio , solo nos queda
    # volver a encapsularlo en un objeto biomoby de respuesta. Pero 
    # en este caso disponemos de una funcion que lo realiza. Si tuvieramos 
    # una respuesta compleja (de verdad, esta era simple ;) llamariamos 
    # a collection response. 
    # IMPORTANTE: el identificador de la respuesta ($queryID) debe ser 
    # el mismo que el de la query. 

    $MOBY_RESPONSE .= simpleResponse($fasta_object, $output_article_name, $queryID);
	
    return $MOBY_RESPONSE;
}


=head2 _do_query_fromFASTAtoMobySequences

 Title   : _do_query_fromFASTAtoMobySequences
         : 
         : private function (NOT EXPORTED)
         : 
 Usage   : my $query_response = _do_query_GeneID($query);
         : 
         : donde:
         :   $query es un XML::DOM::Node que contiene el arbol xml que
         :   engloba:  
         :     <moby:mobyData queryID='1'>...</moby:mobyData>
         : 
 Returns : Devuelve un string que contiene el resultado de la ejecuci�n
         : para una sola query.
         : Un ejemplo ser�a: 
         : 
         : <moby:mobyData moby:queryID='1'>
         :   <moby:Simple moby:articleName='report'>
         :     <moby:text-plain namespace='Global_Keyword' id=''>
	 :    ....
         :     </moby:text-plain>
         :   </moby:Simple>
         : </moby:mobyData>

=cut

sub _do_query_fromFASTAtoMobySequences {
    # $queryInput_DOM es un objeto DOM::Node con la informacion de una query biomoby 
    my $queryInput_DOM   = shift @_;
    my $moby_object_type = shift @_;

    if ($_debug) {
	print STDERR "moby_object_type, $moby_object_type\n";
    }
    
    my $MOBY_RESPONSE = "";     # set empty response
    
    my $fasta_seqs;
    
    my $queryID  = getInputID ($queryInput_DOM);
    my @articles = getArticles($queryInput_DOM);
    
    # Tratamos a cada uno de los articulos
    foreach my $article (@articles) {
	
	# El articulo es una tupla que contiene el nombre de este 
	# y su texto xml. 
	
	my ($articleName, $DOM) = @{$article}; # get the named article
	
	if ($_debug) {
	    print STDERR "processing article, $articleName...\n";
	}
	
	# Si le hemos puesto nombre a los articulos del servicio,  
	# podemos recoger a traves de estos nombres el valor.
	# Sino sabemos que es el input articulo porque es un simple articulo
	
	# It's not very nice but taverna doesn't set up easily article name for input data so we let the users not setting up the article name of the input (which should be 'sequences')
	# In case of GeneID, it doesn't really matter as there is only one input anyway
	
	if (((defined $articleName) && ($articleName eq "sequences")) || isSimpleArticle ($DOM)) {
	    
	    if (isSimpleArticle ($DOM)) {
		
		if ($_debug) {
		    print STDERR "\"sequences\" tag is a simple article...\n";
		    print STDERR "stringified DOM, " . $DOM->toString () . "\n";
		}
		
		$fasta_seqs = INB::GRIB::Utils::CommonUtilsSubs->getTextContentFromXML ($DOM, "FASTA");
		if ((not defined $fasta_seqs) || ($fasta_seqs eq "")) {
		    $fasta_seqs = INB::GRIB::Utils::CommonUtilsSubs->getTextContentFromXML ($DOM, "String");
		}		
	    }
	    elsif (isCollectionArticle ($DOM)) {
		print STDERR "sequences is a collection article...\n";
		# print STDERR "Collection DOM: " . $DOM->toString() . "\n";
		print STDERR "should be receiving a simple article\n";
		exit 0;
	    }
	    else {
		print STDERR "It is not a simple or collection article...\n";
		print STDERR "DOM: " . $DOM->toString() . "\n";
		exit 0;
	    }
	}
	elsif (isCollectionArticle ($DOM)) {
	    print STDERR "input is a collection article...\n";
	    # print STDERR "Collection DOM: " . $DOM->toString() . "\n";
	    print STDERR "should be receiving a simple article\n";
	    exit 0;
	} # End parsing sequences article tag
	else {
	    print STDERR "nothing I know of,\n";
	    print STDERR "$DOM\n";
	}
    } # Next article
    
    # Parse the FASTA sequences
    
    my $namespace = "";
    
    if ($_debug) {
	print STDERR "fasta sequences,\n$fasta_seqs.\n";
    }
    
    my $seqobjs   = INB::GRIB::Utils::CommonUtilsSubs->createSequenceObjectsFromFASTA ($fasta_seqs, $moby_object_type, $namespace);
    
    # Check that we have parsed properly the sequences
    
    if (@$seqobjs == 0) {
	print STDERR "Error, can't parsed any sequences...\n";
    }
    
    my $output_article_name = "sequences";
    $MOBY_RESPONSE .= collectionResponse($seqobjs, $output_article_name, $queryID);
    
    return $MOBY_RESPONSE;
}

=head2 _do_query_generateScoreMatrix

 Title   : _do_query_generateScoreMatrix
         : 
         : private function (NOT EXPORTED)
         : 
 Usage   : my $query_response = _do_query_generateScoreMatrix($query);
         : 
         : donde:
         :   $query es un XML::DOM::Node que contiene el arbol xml que
         :   engloba:  
         :     <moby:mobyData queryID='1'>...</moby:mobyData>
         : 
 Returns : Devuelve un string que contiene el resultado de la ejecuci�n
         : para una sola query.
         : Un ejemplo ser�a: 
         : 
         : <moby:mobyData moby:queryID='1'>
         :   <moby:Simple moby:articleName='report'>
         :     <moby:text-plain namespace='Global_Keyword' id=''>
	 :    ....
         :     </moby:text-plain>
         :   </moby:Simple>
         : </moby:mobyData>

=cut

sub _do_query_generateScoreMatrix {
    # $queryInput_DOM es un objeto DOM::Node con la informacion de una query biomoby 
    my $queryInput_DOM = shift @_;

    my $MOBY_RESPONSE = "";     # set empty response
    
    # Aqui escribimos las variables que necesitamos para la funcion.
    my $input_format;
    my $output_format;
        
    # Variables that will be passed to generateScoreMatrix_call
    
    my %parameters;
    my $input_data = [];
    my $queryID    = getInputID ($queryInput_DOM);
    my @articles   = getArticles($queryInput_DOM);

    # Get the parameters
    
    ($input_format)  = getNodeContentWithArticle($queryInput_DOM, "Parameter", "input format");
    ($output_format) = getNodeContentWithArticle($queryInput_DOM, "Parameter", "output format");
    
    if (not defined $input_format) {
	$input_format = "meta-alignment";
    }
    if (not defined $output_format) {
	$output_format = "SOTA";
    }

    # The moby output format
    # Default is text-formatted
    my $_moby_output_format = "text-formatted";
    if ($output_format eq "Phylip") {
    	$_moby_output_format = "Phylip_matrix_Text";
    }
    elsif ($output_format eq "SOTA") {
	$_moby_output_format = "MicroArrayData_Text";
    }
    
    # Add the parsed parameters in a hash table
    
    if ($_debug) {
	print STDERR "input format, $input_format\n";
	print STDERR "output format, $output_format\n";
	print STDERR "moby_output_format, $_moby_output_format\n";
    }

    $parameters{input_format}  = $input_format;
    $parameters{output_format} = $output_format;

    # Tratamos a cada uno de los articulos
    foreach my $article (@articles) {       
	
	# El articulo es una tupla que contiene el nombre de este 
	# y su texto xml. 
	
	my ($articleName, $DOM) = @{$article}; # get the named article

	if ($_debug) {
	    print STDERR "processing article, $articleName...\n";
	}
	
	# Si le hemos puesto nombre a los articulos del servicio,  
	# podemos recoger a traves de estos nombres el valor.
	# Sino sabemos que es el input articulo porque es un simple/collection articulo

	# It's not very nice but taverna doesn't set up easily article name for input data so we let the users not setting up the article name of the input (which should be 'sequences')

	if ((isCollectionArticle ($DOM)) || (defined ($articleName) && ($articleName eq "similarity_results"))) {

	    if (isSimpleArticle($DOM)) {
		print STDERR "problem, input article is simple - should be a collection!!!\n";
		exit 0;
	    }
	    
	    if ($_debug) {
		print STDERR "node ref, " . ref ($DOM) . "\n";
		print STDERR "DOM: " . $DOM->toString () . "\n";
	    }
	    
	    my @inputs_article_DOMs = getCollectedSimples ($DOM);
	    foreach my $input_DOM (@inputs_article_DOMs) {
		
		# check that out, could well not be text-formatted but GFF !!!
		my $input = INB::GRIB::Utils::CommonUtilsSubs->getTextContentFromXML ($input_DOM, "text-formatted");
		if (not defined $input) {
		    $input = INB::GRIB::Utils::CommonUtilsSubs->getTextContentFromXML ($input_DOM, "GFF");
		}
		if (not defined $input) {
		    print STDERR "Error, can't parse any input!!\n";
		    exit 0;
		}
		
		if ($_debug) {
		    print STDERR "input, $input\n";
		}
		
		push (@$input_data, $input);
		
	    }
	}	
	
    } # Next article

    my $matrix = generateScoreMatrix_call (similarity_results  => $input_data, parameters => \%parameters);

    # Ahora que tenemos la salida en el formato de la aplicacion XXXXXXX 
    # nos queda encapsularla en un Objeto bioMoby. Esta operacio 
    # la podriamos realizar en una funcion a parte si fuese compleja.  
		    
    my $namespace = "";
    
    # Build the Moby object
    
    my $output_object = <<PRT;
<moby:$_moby_output_format namespace='$namespace' id=''>
<![CDATA[
$matrix
]]>
</moby:$_moby_output_format>
PRT

    # Bien!!! ya tenemos el objeto de salida del servicio , solo nos queda
    # volver a encapsularlo en un objeto biomoby de respuesta. Pero 
    # en este caso disponemos de una funcion que lo realiza. Si tuvieramos 
    # una respuesta compleja (de verdad, esta era simple ;) llamariamos 
    # a collection response. 
    # IMPORTANTE: el identificador de la respuesta ($queryID) debe ser 
    # el mismo que el de la query.
    
    my $output_article_name = "score_matrix";
    $MOBY_RESPONSE .= simpleResponse($output_object, $output_article_name, $queryID);
    
    return $MOBY_RESPONSE;
}



#################################
# Interface service methods
#################################


=head2 translateGeneIDGFFPredictions

 Title   : translateGeneIDGFFPredictions
 Usage   : Esta funci�n est� pensada para llamarla desde un cliente SOAP. 
         : No obstante, se recomienda probarla en la misma m�quina, antes 
         : de instalar el servicio. Para ello, podemos llamarla de la 
         : siguiente forma:
         : 
         : my $result = GeneID("call", $in);
         : 
         : donde $in es texto que con el mensaje biomoby que contendr�a
         : la parte del <tag> "BODY" del mensaje soap. Es decir, un string
         : de la forma: 
         :  
         :  <?xml version='1.0' encoding='UTF-8'?>
         :   <moby:MOBY xmlns:moby='http://www.biomoby.org/moby-s'>
         :    <moby:mobyContent>
         :      <moby:mobyData queryID='1'> 
         :      ...
         :      </moby:mobyData>
         :    </moby:mobyContent>
         :   </moby:mobyContent>
         :  </moby:MOBY>
 Returns : Devuelve un string que contiene el resultado de todas las 
         : queries en GFF formate. Es decir, un mensaje xml de la forma:
         :
         : <?xml version='1.0' encoding='UTF-8'?>
         : <moby:MOBY xmlns:moby='http://www.biomoby.org/moby' 
         : xmlns='http://www.biomoby.org/moby'>
         :   <moby:mobyContent moby:authority='inb.lsi.upc.es'>
         :     <moby:mobyData moby:queryID='1'>
         :       ....
         :     </moby:mobyData>
         :     <moby:mobyData moby:queryID='2'>
         :       ....
         :     </moby:mobyData>
         :   </moby:mobyContent>
         :</moby:MOBY>

=cut

sub translateGeneIDGFFPredictions {
    
    # El parametro $message es un texto xml con la peticion.
    my ($caller, $message) = @_;        # get the incoming MOBY query XML

    if ($_debug) {
	print STDERR "processing Moby translateGeneIDGFFPredictions query...\n";
    }

	# Hasta el momento, no existen objetos Perl de BioMoby paralelos 
	# a la ontologia, y debemos contentarnos con trabajar directamente 
	# con objetos DOM. Por consiguiente lo primero es recolectar la 
	# lista de peticiones (queries) que tiene la peticion. 
	# 
	# En una misma llamada podemos tener mas de una peticion, y de  
	# cada servicio depende la forma de trabajar con ellas. En este 
	# caso las trataremos una a una, pero podriamos hacer Threads para 
	# tratarlas en paralelo, podemos ver si se pueden aprovechar resultados 
	# etc.. 
	my @queries = getInputs($message);  # returns XML::DOM nodes
	# 
	# Inicializamos la Respuesta a string vacio. Recordar que la respuesta
	# es una coleccion de respuestas a cada una de las consultas.
        my $MOBY_RESPONSE = "";             # set empty response

	# Para cada query ejecutaremos el _execute_query.
        foreach my $queryInput (@queries){

	    # En este punto es importante recordar que el objeto $query 
	    # es un XML::DOM::Node, y que si queremos trabajar con 
	    # el mensaje de texto debemos llamar a: $query->toString() 
	    
	    if ($_debug) {
		my $query_str = $queryInput->toString();
		print STDERR "query text: $query_str\n";
	    }

	    my $query_response = _do_query_TranslateGeneIDGFF ($queryInput);
	    
	    # $query_response es un string que contiene el codigo xml de
	    # la respuesta.  Puesto que es un codigo bien formado, podemos 
	    # encadenar sin problemas una respuesta con otra. 
	    $MOBY_RESPONSE .= $query_response;
	}
	# Una vez tenemos la coleccion de respuestas, debemos encapsularlas 
	# todas ellas con una cabecera y un final. Esto lo podemos hacer 
	# con las llamadas de la libreria Common de BioMoby. 
	return responseHeader("genome.imim.es") 
	. $MOBY_RESPONSE . responseFooter;
}

=head2 fromGenericSequencetoFASTA

 Title   : fromGenericSequencetoFASTA
 Usage   : Esta funci�n est� pensada para llamarla desde un cliente SOAP. 
         : No obstante, se recomienda probarla en la misma m�quina, antes 
         : de instalar el servicio. Para ello, podemos llamarla de la 
         : siguiente forma:
         : 
         : my $result = GeneID("call", $in);
         : 
         : donde $in es texto que con el mensaje biomoby que contendr�a
         : la parte del <tag> "BODY" del mensaje soap. Es decir, un string
         : de la forma: 
         :  
         :  <?xml version='1.0' encoding='UTF-8'?>
         :   <moby:MOBY xmlns:moby='http://www.biomoby.org/moby-s'>
         :    <moby:mobyContent>
         :      <moby:mobyData queryID='1'> 
         :      ...
         :      </moby:mobyData>
         :    </moby:mobyContent>
         :   </moby:mobyContent>
         :  </moby:MOBY>
 Returns : Devuelve un string que contiene el resultado de todas las 
         : queries en GFF formate. Es decir, un mensaje xml de la forma:
         :
         : <?xml version='1.0' encoding='UTF-8'?>
         : <moby:MOBY xmlns:moby='http://www.biomoby.org/moby' 
         : xmlns='http://www.biomoby.org/moby'>
         :   <moby:mobyContent moby:authority='inb.lsi.upc.es'>
         :     <moby:mobyData moby:queryID='1'>
         :       ....
         :     </moby:mobyData>
         :     <moby:mobyData moby:queryID='2'>
         :       ....
         :     </moby:mobyData>
         :   </moby:mobyContent>
         :</moby:MOBY>

=cut

sub fromGenericSequencetoFASTA {
    
    # El parametro $message es un texto xml con la peticion.
    my ($caller, $message) = @_;        # get the incoming MOBY query XML

    if ($_debug) {
	print STDERR "processing Moby fromGenericSequencetoFASTA query...\n";
    }

	# Hasta el momento, no existen objetos Perl de BioMoby paralelos 
	# a la ontologia, y debemos contentarnos con trabajar directamente 
	# con objetos DOM. Por consiguiente lo primero es recolectar la 
	# lista de peticiones (queries) que tiene la peticion. 
	# 
	# En una misma llamada podemos tener mas de una peticion, y de  
	# cada servicio depende la forma de trabajar con ellas. En este 
	# caso las trataremos una a una, pero podriamos hacer Threads para 
	# tratarlas en paralelo, podemos ver si se pueden aprovechar resultados 
	# etc.. 
	my @queries = getInputs($message);  # returns XML::DOM nodes
	# 
	# Inicializamos la Respuesta a string vacio. Recordar que la respuesta
	# es una coleccion de respuestas a cada una de las consultas.
        my $MOBY_RESPONSE = "";             # set empty response

	# Para cada query ejecutaremos el _execute_query.
        foreach my $queryInput (@queries){

	    # En este punto es importante recordar que el objeto $query 
	    # es un XML::DOM::Node, y que si queremos trabajar con 
	    # el mensaje de texto debemos llamar a: $query->toString() 
	    
	    if ($_debug) {
		my $query_str = $queryInput->toString();
		print STDERR "query text: $query_str\n";
	    }

	    my $query_response = _do_query_fromGenericSequencestoFASTA ($queryInput);
	    
	    # $query_response es un string que contiene el codigo xml de
	    # la respuesta.  Puesto que es un codigo bien formado, podemos 
	    # encadenar sin problemas una respuesta con otra. 
	    $MOBY_RESPONSE .= $query_response;
	}
	# Una vez tenemos la coleccion de respuestas, debemos encapsularlas 
	# todas ellas con una cabecera y un final. Esto lo podemos hacer 
	# con las llamadas de la libreria Common de BioMoby. 
	return responseHeader("genome.imim.es") 
	. $MOBY_RESPONSE . responseFooter;
}

=head2 fromGenericSequenceCollectiontoFASTA

 Title   : fromGenericSequenceCollectiontoFASTA
 Usage   : Esta funci�n est� pensada para llamarla desde un cliente SOAP. 
         : No obstante, se recomienda probarla en la misma m�quina, antes 
         : de instalar el servicio. Para ello, podemos llamarla de la 
         : siguiente forma:
         : 
         : my $result = GeneID("call", $in);
         : 
         : donde $in es texto que con el mensaje biomoby que contendr�a
         : la parte del <tag> "BODY" del mensaje soap. Es decir, un string
         : de la forma: 
         :  
         :  <?xml version='1.0' encoding='UTF-8'?>
         :   <moby:MOBY xmlns:moby='http://www.biomoby.org/moby-s'>
         :    <moby:mobyContent>
         :      <moby:mobyData queryID='1'> 
         :      ...
         :      </moby:mobyData>
         :    </moby:mobyContent>
         :   </moby:mobyContent>
         :  </moby:MOBY>
 Returns : Devuelve un string que contiene el resultado de todas las 
         : queries en GFF formate. Es decir, un mensaje xml de la forma:
         :
         : <?xml version='1.0' encoding='UTF-8'?>
         : <moby:MOBY xmlns:moby='http://www.biomoby.org/moby' 
         : xmlns='http://www.biomoby.org/moby'>
         :   <moby:mobyContent moby:authority='inb.lsi.upc.es'>
         :     <moby:mobyData moby:queryID='1'>
         :       ....
         :     </moby:mobyData>
         :     <moby:mobyData moby:queryID='2'>
         :       ....
         :     </moby:mobyData>
         :   </moby:mobyContent>
         :</moby:MOBY>

=cut

sub fromGenericSequenceCollectiontoFASTA {
    
    # El parametro $message es un texto xml con la peticion.
    my ($caller, $message) = @_;        # get the incoming MOBY query XML

    if ($_debug) {
	print STDERR "processing Moby fromGenericSequenceCollectiontoFASTA query...\n";
    }

	# Hasta el momento, no existen objetos Perl de BioMoby paralelos 
	# a la ontologia, y debemos contentarnos con trabajar directamente 
	# con objetos DOM. Por consiguiente lo primero es recolectar la 
	# lista de peticiones (queries) que tiene la peticion. 
	# 
	# En una misma llamada podemos tener mas de una peticion, y de  
	# cada servicio depende la forma de trabajar con ellas. En este 
	# caso las trataremos una a una, pero podriamos hacer Threads para 
	# tratarlas en paralelo, podemos ver si se pueden aprovechar resultados 
	# etc.. 
	my @queries = getInputs($message);  # returns XML::DOM nodes
	# 
	# Inicializamos la Respuesta a string vacio. Recordar que la respuesta
	# es una coleccion de respuestas a cada una de las consultas.
        my $MOBY_RESPONSE = "";             # set empty response

	# Para cada query ejecutaremos el _execute_query.
        foreach my $queryInput (@queries){

	    # En este punto es importante recordar que el objeto $query 
	    # es un XML::DOM::Node, y que si queremos trabajar con 
	    # el mensaje de texto debemos llamar a: $query->toString() 
	    
	    if ($_debug) {
		my $query_str = $queryInput->toString();
		print STDERR "query text: $query_str\n";
	    }

	    my $query_response = _do_query_fromGenericSequencestoFASTA ($queryInput);
	    
	    # $query_response es un string que contiene el codigo xml de
	    # la respuesta.  Puesto que es un codigo bien formado, podemos 
	    # encadenar sin problemas una respuesta con otra. 
	    $MOBY_RESPONSE .= $query_response;
	}
	# Una vez tenemos la coleccion de respuestas, debemos encapsularlas 
	# todas ellas con una cabecera y un final. Esto lo podemos hacer 
	# con las llamadas de la libreria Common de BioMoby. 
	return responseHeader("genome.imim.es") 
	. $MOBY_RESPONSE . responseFooter;
}


=head2 fromFASTAtoDNASequenceCollection

 Title   : fromDNASequenceCollectiontoFASTA
 Usage   : Esta funci�n est� pensada para llamarla desde un cliente SOAP. 
         : No obstante, se recomienda probarla en la misma m�quina, antes 
         : de instalar el servicio. Para ello, podemos llamarla de la 
         : siguiente forma:
         : 
         : my $result = GeneID("call", $in);
         : 
         : donde $in es texto que con el mensaje biomoby que contendr�a
         : la parte del <tag> "BODY" del mensaje soap. Es decir, un string
         : de la forma: 
         :  
         :  <?xml version='1.0' encoding='UTF-8'?>
         :   <moby:MOBY xmlns:moby='http://www.biomoby.org/moby-s'>
         :    <moby:mobyContent>
         :      <moby:mobyData queryID='1'> 
         :      ...
         :      </moby:mobyData>
         :    </moby:mobyContent>
         :   </moby:mobyContent>
         :  </moby:MOBY>
 Returns : Devuelve un string que contiene el resultado de todas las 
         : queries en GFF formate. Es decir, un mensaje xml de la forma:
         :
         : <?xml version='1.0' encoding='UTF-8'?>
         : <moby:MOBY xmlns:moby='http://www.biomoby.org/moby' 
         : xmlns='http://www.biomoby.org/moby'>
         :   <moby:mobyContent moby:authority='inb.lsi.upc.es'>
         :     <moby:mobyData moby:queryID='1'>
         :       ....
         :     </moby:mobyData>
         :     <moby:mobyData moby:queryID='2'>
         :       ....
         :     </moby:mobyData>
         :   </moby:mobyContent>
         :</moby:MOBY>

=cut

sub fromFASTAtoDNASequenceCollection {
    
    # El parametro $message es un texto xml con la peticion.
    my ($caller, $message) = @_;        # get the incoming MOBY query XML

    if ($_debug) {
	print STDERR "processing Moby fromFASTAtoDNASequenceCollection query...\n";
    }

	# Hasta el momento, no existen objetos Perl de BioMoby paralelos 
	# a la ontologia, y debemos contentarnos con trabajar directamente 
	# con objetos DOM. Por consiguiente lo primero es recolectar la 
	# lista de peticiones (queries) que tiene la peticion. 
	# 
	# En una misma llamada podemos tener mas de una peticion, y de  
	# cada servicio depende la forma de trabajar con ellas. En este 
	# caso las trataremos una a una, pero podriamos hacer Threads para 
	# tratarlas en paralelo, podemos ver si se pueden aprovechar resultados 
	# etc.. 
	my @queries = getInputs($message);  # returns XML::DOM nodes
	# 
	# Inicializamos la Respuesta a string vacio. Recordar que la respuesta
	# es una coleccion de respuestas a cada una de las consultas.
        my $MOBY_RESPONSE = "";             # set empty response

	# Para cada query ejecutaremos el _execute_query.
        foreach my $queryInput (@queries){

	    # En este punto es importante recordar que el objeto $query 
	    # es un XML::DOM::Node, y que si queremos trabajar con 
	    # el mensaje de texto debemos llamar a: $query->toString() 
	    
	    if ($_debug) {
		my $query_str = $queryInput->toString();
		print STDERR "query text: $query_str\n";
	    }

	    my $query_response = _do_query_fromFASTAtoMobySequences ($queryInput, "DNASequence");
	    
	    # $query_response es un string que contiene el codigo xml de
	    # la respuesta.  Puesto que es un codigo bien formado, podemos 
	    # encadenar sin problemas una respuesta con otra. 
	    $MOBY_RESPONSE .= $query_response;
	}
	# Una vez tenemos la coleccion de respuestas, debemos encapsularlas 
	# todas ellas con una cabecera y un final. Esto lo podemos hacer 
	# con las llamadas de la libreria Common de BioMoby. 
	return responseHeader("genome.imim.es") 
	. $MOBY_RESPONSE . responseFooter;
}


=head2 generateScoreMatrix

 Title   : generateScoreMatrix
 Usage   : Esta funci�n est� pensada para llamarla desde un cliente SOAP. 
         : No obstante, se recomienda probarla en la misma m�quina, antes 
         : de instalar el servicio. Para ello, podemos llamarla de la 
         : siguiente forma:
         : 
         : my $result = GeneID("call", $in);
         : 
         : donde $in es texto que con el mensaje biomoby que contendr�a
         : la parte del <tag> "BODY" del mensaje soap. Es decir, un string
         : de la forma: 
         :  
         :  <?xml version='1.0' encoding='UTF-8'?>
         :   <moby:MOBY xmlns:moby='http://www.biomoby.org/moby-s'>
         :    <moby:mobyContent>
         :      <moby:mobyData queryID='1'> 
         :      ...
         :      </moby:mobyData>
         :    </moby:mobyContent>
         :   </moby:mobyContent>
         :  </moby:MOBY>
 Returns : Devuelve un string que contiene el resultado de todas las 
         : queries en GFF formate. Es decir, un mensaje xml de la forma:
         :
         : <?xml version='1.0' encoding='UTF-8'?>
         : <moby:MOBY xmlns:moby='http://www.biomoby.org/moby' 
         : xmlns='http://www.biomoby.org/moby'>
         :   <moby:mobyContent moby:authority='inb.lsi.upc.es'>
         :     <moby:mobyData moby:queryID='1'>
         :       ....
         :     </moby:mobyData>
         :     <moby:mobyData moby:queryID='2'>
         :       ....
         :     </moby:mobyData>
         :   </moby:mobyContent>
         :</moby:MOBY>

=cut

sub generateScoreMatrix {
    
    # El parametro $message es un texto xml con la peticion.
    my ($caller, $message) = @_;        # get the incoming MOBY query XML

    if ($_debug) {
	print STDERR "processing Moby generateScoreMatrix query...\n";
    }

	# Hasta el momento, no existen objetos Perl de BioMoby paralelos 
	# a la ontologia, y debemos contentarnos con trabajar directamente 
	# con objetos DOM. Por consiguiente lo primero es recolectar la 
	# lista de peticiones (queries) que tiene la peticion. 
	# 
	# En una misma llamada podemos tener mas de una peticion, y de  
	# cada servicio depende la forma de trabajar con ellas. En este 
	# caso las trataremos una a una, pero podriamos hacer Threads para 
	# tratarlas en paralelo, podemos ver si se pueden aprovechar resultados 
	# etc.. 
	my @queries = getInputs($message);  # returns XML::DOM nodes
	# 
	# Inicializamos la Respuesta a string vacio. Recordar que la respuesta
	# es una coleccion de respuestas a cada una de las consultas.
        my $MOBY_RESPONSE = "";             # set empty response

	# Para cada query ejecutaremos el _execute_query.
        foreach my $queryInput (@queries){

	    # En este punto es importante recordar que el objeto $query 
	    # es un XML::DOM::Node, y que si queremos trabajar con 
	    # el mensaje de texto debemos llamar a: $query->toString() 
	    
	    if ($_debug) {
		my $query_str = $queryInput->toString();
		print STDERR "query text: $query_str\n";
	    }

	    my $query_response = _do_query_generateScoreMatrix ($queryInput);
	    
	    # $query_response es un string que contiene el codigo xml de
	    # la respuesta.  Puesto que es un codigo bien formado, podemos 
	    # encadenar sin problemas una respuesta con otra. 
	    $MOBY_RESPONSE .= $query_response;
	}
	# Una vez tenemos la coleccion de respuestas, debemos encapsularlas 
	# todas ellas con una cabecera y un final. Esto lo podemos hacer 
	# con las llamadas de la libreria Common de BioMoby. 
	return responseHeader("genome.imim.es") 
	. $MOBY_RESPONSE . responseFooter;
}


1;

__END__

