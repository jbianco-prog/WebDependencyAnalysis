#! perl -w

use strict;									## On utilise une synthaxe stricte
use LWP::Simple;								## On utilise la lib standard
use URI::Find;									## On utilise la lib URI-Find
#use Gtk2 '-init'; 								## Pour les appels de génération du graphe

system ("clear");								## On clean l'écran

if(!$ARGV[0])									## Test contrôle d'erreur
{
	print "\n# ERREUR 1 : Veuillez saisir l'adresse du site web.\nusage : ./audit.pl <URL du site web : www.siteweb.com>\n\n";
	exit(1);
}
else
{
## Configuration générale :

# Entêtes HTTP
	my $http_header="http://";						## On définit les entêtes HTTP
# Entêtes HTTPS
	my $https_header="http://";						## On définit les entêtes HTTPS
# Adresse du site web
	my $site=$ARGV[0];							## On stocke le nom de domaine en globale
# Serveur HTTP
	my $addr=$http_header.$site;						## Par défaut, on utilise HTTP, puis HTTPS
# Serveur HTTPS (Secure avec SSL)
#	my $addr=$https_header.$site;						## Par défaut, on utilise HTTPS, puis HTTP
# Fichier de dépot pour traitement
	my $file=".audit.html";							## On construit un fichier temporaire de dépot
# Fichier de data (.dot)
	my $xml_file=".xml_file.xml";						## On construit un fichier de data (.dot)

## Script - déclarations
	my $var;								## On construit une variable de test
	my $nb=0;								## On initialise le compteur
	my @lien=();								## On créer un tableau en globale

## Script - suppression des résidus
	system ("rm -f xml_file.xml");						## Suppression du fichier de data (.dot)
	system ("rm -f .audit.html");						## Suppression du fichier de dépot
	system ("rm -f architecture.jpg");					## Suppression du graphe précédent

	print "\nAudit du site web : $site\n";					## On affiche la racine du site web en mode texte

	if(!getstore($addr."/",'.audit.html'))
	{
		my $addr_ssl=$https_header.$site;
		if(!getstore($addr_ssl."/",'.audit.html'))
		{
			print "\n# ERREUR 2 : Impossible d'accèder au site web.\nusage : ./audit.pl <URL du site web : www.siteweb.com>\n\n";
			system ("rm -f .audit.html");
			system ("rm -f xml_file.xml");
		}
	}

	if(!open(FICHIER_XML,'> xml_file.xml'))
	{
		print "\n# ERREUR 4 : Impossible d'ouvrir le fichier xml_file.\n\n\n";
		exit(4);
	}

## Script - on écrit les entêtes au fichier xml
	print FICHIER_XML "digraph G {\n";
	print FICHIER_XML "\tbgcolor=white;";
	print FICHIER_XML "\tnode [shape=box, style=filled, fillcolor=white];\n";
	print FICHIER_XML "\tedge [color=black, len=5];\n";

## Script - on scan le dépot
	if(!open(FICHIER,'.audit.html')) 
	{
		print "\n# ERREUR 3 : Veuillez vérifier l'URL saisie.\n\n\n";
		system ("rm -f .audit.html");
		system ("rm -f xml_file.xml");
		exit(3);
	}

	else
	{
		while(my $line=<FICHIER>)
		{
		find_uris($line, 
			sub {
				my($url, $original_uri) = @_;
				$var=0;
			if(($url=~ /^$addr/) && $var==0)
			{
				push(@lien, $url);
				print FICHIER_XML "\"$addr\" -> \"$url\";\n";
			}
			});
		}
	close FICHIER;
	}

	my $start=0;
	my $end_loop=($#lien+1);
	my @lien1=@lien;

	for($nb=$start;$nb<$end_loop;$nb++)
	{
		$addr=$lien[$nb];
		print "\nArborescence de : $addr \n\n";

		if(!getstore($addr."/",'.audit.html'))
		{
			my $addr_ssl=$https_header.$site;
			if(!getstore($addr_ssl."/",'.audit.html'))
			{
				print "\n# ERREUR 2 : Impossible d'accèder au site web.\nusage : ./audit.pl <URL du site web : www.siteweb.com>\n\n";
				system ("rm -f .audit.html");
				system ("rm -f xml_file.xml");
			}
		}
	 	if(!open(FICHIER,'.audit.html'))
		{
			print "\n# ERREUR 4 : Impossible d'ouvrir le fichier .audit.html\n\n\n";
			exit (4);
		}
		else
		{
			while(my $line=<FICHIER>)
			{
				find_uris($line, 
				sub
				{
					my($url, $original_uri)= @_;
					$var=0;	
					print("$url\n");
					print FICHIER_XML "\"$addr\" -> \"$url\";\n";
					foreach $nb (@lien)
					{
						if ($nb eq $url)
						{
							$var=1;
						}
					}
					if(($url=~ /^$addr/) && $var==0) 
					{
						push(@lien, $url);
						print FICHIER_XML "\"$addr\" -> \"$url\";\n";
						return $original_uri;
					}
				});
			}
			close FICHIER;
		}

	if($nb==($end_loop-1))
	{ 
		$start=$end_loop; 
		$end_loop=($#lien+1);
	}
	@lien1=@lien;
	}

	print FICHIER_XML "}"; 
	close FICHIER_XML;

#	print "\nArborescence site web :\n\n"; 
#	print join("\n", @lien), "\n";

	exec ("neato -Tjpg -o architecture.jpg xml_file.xml");			## Génération du graphe	
	system ("rm -f .audit.html");						## Suppression du fichier de dépot
	print "\nGraphe généré : architecture.jpg\n\n";
}										## Fin contrôle d'erreur
