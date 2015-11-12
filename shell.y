
/*
 * CS-252 Spring 2015
 * shell.y: parser for shell
 *
 * This parser compiles the following grammar:
 *
 *	cmd [arg]* [> filename]
 *
 * You must extend it to understand the complete shell grammar.
 *
 */

%token	<string_val> WORD SUBSHELLCMD

%token 	NOTOKEN GREAT NEWLINE PIPE AMP LESS  GREATAMP GREATGREAT GREATGREATAMP EXIT
%union	{
		char   *string_val;
	}

%{
//#define yylex yylex
#include <stdio.h>
#include "command.h"
#include <pwd.h>
#include <string.h>
#include <regex.h>
#include <dirent.h>
#include <assert.h>

#include "tty.h"

void yyerror(const char * s);
int yylex();

int outputflag;
int inputflag;

void expandWildcardIfNecessary(char * arg);
int string_cmp(const char * a, const char * b);
void expandWildcard(char* prefix, char * suffix);

%}

%%

goal:	
	commands
	;

commands: 
	command
	| commands command 
	;

command: simple_command
	|
        ;

simple_command:	
	pipe_list io_list {
		//printf("   Yacc: Execute command\n");
		Command::_currentCommand.execute();
	}
	| NEWLINE 
	| error NEWLINE { yyerrok; }
	;

io_list:
	iomodifier_opt io_list
	|
	iomodifier_opt
	|
	NEWLINE
	;

pipe_list:
	pipe_list PIPE command_and_args
	|
	command_and_args
	;

command_and_args:
	command_word arg_list {
		Command::_currentCommand.
			insertSimpleCommand( Command::_currentSimpleCommand );
			outputflag = 0;
	}
	;

arg_list:
	arg_list argument
	| /* can be empty */

	;



argument:
	WORD {
		char* arg;
		arg = $1;
		if(arg[0] == '~'){
			if(arg[1] == '\0'){
				char* string = (char *)malloc(sizeof(strlen(getenv("HOME"))));
				strcpy(string, getenv("HOME"));
				Command::_currentSimpleCommand->insertArgument( string );
			}
			else{
				int found = 0;
				for(int i = 0; i < strlen(arg); i++)
					if(arg[i] == '/')
						found = 1;
				if(found == 0){
					char* dir1 = (char *)malloc(sizeof(strlen(arg)));
					int i = 0;
					int j;
					for(j = 1; arg[j] != '\0'; j++){
						dir1[i] = arg[j];
						i++;
					}
					dir1[i] = '\0';
					struct passwd* pw = getpwnam(dir1);
					char* string = (char *)malloc(sizeof(strlen(pw->pw_dir)));
					strcpy(string, pw->pw_dir);
					Command::_currentSimpleCommand->insertArgument( string );					
				}
				else{
					char* dir1 = (char *)malloc(sizeof(strlen(arg)));
					int i = 0;
					int j;
					for(j = 1; arg[j] != '/'; j++){
						dir1[i] = arg[j];
						i++;
					}
					dir1[i] = '\0';
					struct passwd* pw = getpwnam(dir1);
					j++;
					char* dir2 = (char *)malloc(sizeof(strlen(arg)));
					i = 0;
					int l;
					for(l = j; arg[l] != '\0'; l++){
						dir2[i] = arg[l];
						i++;				
					}
					dir2[i] = '\0';
					//char* string = (char *)malloc(sizeof(strlen(pw->pw_dir)+ strlen(dir2) + 1));
					strcat(pw->pw_dir, dir2);
					expandWildcardIfNecessary( pw->pw_dir );
				}
			}			

		}
		else
			expandWildcardIfNecessary( $1);
	}
	|
	SUBSHELLCMD{
		printf("SUBSHELL: %s\n", $1);
	}
	;

command_word:
	WORD {

	       		Command::_currentSimpleCommand = new SimpleCommand();
				Command::_currentSimpleCommand->insertArgument( $1 );
	}
	|
	EXIT{
		ttyteardown();
		exit(0);
	}
	;

iomodifier_opt:
	AMP{
		Command::_currentCommand._background = 1;
	}
	| 
	LESS WORD {
		if(inputflag == 0)
			inputflag = 1;
		else{
			Command::_currentCommand.errorflag = 1;
			printf("Ambiguous output redirect");
		}
		//printf("   Yacc: insert input \"%s\"\n", $2);
		Command::_currentCommand._inputFile = $2;
	}
	| 
	GREAT WORD {
		if(outputflag == 0)
			outputflag = 1;
		else{
			Command::_currentCommand.errorflag = 1;
			printf("Ambiguous output redirect");
		}
		//printf("   Yacc: insert output \"%s\"\n", $2);
		Command::_currentCommand._outFile = $2;
	}
	|
	GREATGREAT WORD {
		if(outputflag == 0)
			outputflag = 1;
		else{
			Command::_currentCommand.errorflag = 1;
			printf("Ambiguous output redirect");
		}
	//	printf("   Yacc: insert output \"%s\"\n", $2);
		Command::_currentCommand._outFile = $2;
		Command::_currentCommand.appendflag = 1;
	}
	|
	GREATAMP WORD {
		if(outputflag == 0)
		        outputflag = 1;	
		else{
			Command::_currentCommand.errorflag = 1;
			printf("Ambiguous output redirect");
		}
		//printf("   Yacc: insert output \"%s\"\n", $2);
		Command::_currentCommand._outFile = $2;
		Command::_currentCommand._errFile = $2;
		//greatamp
	}
	|
	GREATGREATAMP WORD {
		if(outputflag == 0)
			outputflag = 1;
		else{
			Command::_currentCommand.errorflag = 1;
			printf("Ambigious otuput redirect\n");
		}
		//printf("   Yacc: insert output \"%s\"\n", $2);
		Command::_currentCommand._outFile = $2;
		Command::_currentCommand._errFile = $2;
		Command::_currentCommand.appendflag = 1;

	}
	;

%%

void expandWildcardIfNecessary(char * arg){

	int flag;
	for(int i = 0; i < strlen(arg); i++){
		if(arg[i] == '*' || arg[i] == '?')
			flag = 1;
	}
	if(flag == 1){
		expandWildcard((char *)"", arg);
	}
	else 
		Command::_currentSimpleCommand->insertArgument( arg );
}


int string_cmp(const void *a, const void *b) 
{ 
    const char **ia = (const char **)a;
    const char **ib = (const char **)b;
    return strcmp(*ia, *ib);
} 

#define MAXFILENAME 1024

void expandWildcard(char * prefix, char * suffix){
	if(suffix[0] == 0){
		Command::_currentSimpleCommand->insertArgument(strdup(prefix));
		return;
	}
	char * s = strchr(suffix, '/');
	char component[MAXFILENAME];
	if(s != NULL){
		strncpy(component, suffix, s-suffix);
		component[s-suffix] = '\0';
		suffix = s + 1;
	}
	else{
		strcpy(component, suffix);
		
		suffix = suffix + strlen(suffix);
	}


	char newPrefix[MAXFILENAME];

	if(!strchr(component,'*') && !strchr(component,'?')){

		if(strcmp(prefix, "/") == 0)
			sprintf(newPrefix, "%s%s", prefix, component);

		else
			sprintf(newPrefix, "%s/%s", prefix, component);



		expandWildcard(newPrefix, suffix);
		return;
	}	
	char * reg = (char *)malloc(2*strlen(component)+10);
	char * a = component;
	char * r = reg;
	*r = '^';
	r++;
	while(*a){
		if(*a == '*'){
			*r = '.';
			r++;
			*r = '*';
			r++;
		}
		else if(*a == '?'){
			*r = '.';
			r++;
		}
		else if(*a == '.'){
			*r = '\\';
			r++;
			*r = '.';
			r++;
		}
		else{
			*r = *a;
			r++;
		}
		a++;
	}
	*r = '\0';
	regex_t re;	
	int result = regcomp( &re, reg,  REG_EXTENDED|REG_NOSUB);
	if( result != 0 ) {
		fprintf( stderr, "%s: Bad regular expresion \"%s\"\n",component, reg );
		exit( -1 );
     }
	DIR * d;
	if(strcmp(prefix, "") == 0 ){			
		d = opendir(".");
	}
	else{
		d = opendir(prefix);
	}
	if(d == NULL){
		return;
	}
	struct dirent * ent;
	int maxEntries = 20;
	int nEntries = 0;
	char ** array = (char **) malloc(maxEntries*sizeof(char *));

	regmatch_t match;
	while((ent = readdir(d))!=NULL){
 		result = regexec( &re, ent->d_name, 1, &match, 0 );
		if(result == 0){
			if(ent->d_name[0] == '.' ){
   				if(  component[0]=='.'){
			        if(nEntries == maxEntries){
						maxEntries *= 2;
						array = (char **)realloc(array, maxEntries*sizeof(char **));
						assert(array != NULL);
					}   
					array[nEntries] = strdup(ent->d_name);
					nEntries++;     
				}
			}
			else{	
				if(nEntries == maxEntries){
					maxEntries *= 2;
					array = (char **)realloc(array, maxEntries*sizeof(char **));
					assert(array != NULL);
				}
					if(prefix[0] == '/' && prefix[1] == '\0')
						sprintf(newPrefix, "%s%s", prefix, ent->d_name);
					else if(strcmp(prefix, "") != 0)
						sprintf(newPrefix, "%s/%s", prefix, ent->d_name);
					else
						sprintf(newPrefix, "%s%s", prefix, ent->d_name);
					array[nEntries] = strdup(newPrefix);
					nEntries++;
			}

		}
	}
	qsort(array, nEntries, sizeof(char *), string_cmp);
	for(int i = 0; i < nEntries; i++){
		expandWildcard(array[i],suffix);
		free(array[i]);
	}
	free(array);
	
}


void
yyerror(const char * s)
{
	fprintf(stderr,"%s", s);
}

#if 0
main()
{
	yyparse();
}
#endif
