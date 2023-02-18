%{
#include "y.tab.h"
#include <string.h>
void yyerror (char *s);
int yylex();
%}
%%
#.*                   {;}
":"                   {return colon;}
","                   {return comma;}
"+"                   {return plus;}
"-"                   {return minus;}
"*"                   {return asterisk;}
"["                   {return left_square_bracket;}
"]"                   {return right_square_bracket;}
"%"                   {return percent;}
"$"                   {return dollar;}
"\n"                  {return new_line;}
\".*\"                {return string;}
".global"             {return global;}
".extern"             {return external;}
".section"				    {return section;}
".word"               {return word;}
".skip"               {return skip;}
".ascii"              {return ascii;}
".equ"                {return equ;}
".end"				        {return end;}
"halt"				        {return halt;}
"int"				          {return interrupt;}
"iret"				        {return iret;}
"call"				        {return call;}
"ret"				        {return ret;}
"jmp"				        {return jmp;}
"jeq"				        {return jeq;}
"jne"				        {return jne;}
"jgt"				        {return jgt;}
"push"				        {return push;}
"pop"				        {return pop;}
"xchg"				        {return xchg;}
"add"				        {return add;}
"sub"				        {return sub;}
"mul"				        {return mul;}
"div"				        {return divide;}
"cmp"				        {return cmp;}
"not"				        {return not;}
"and"				        {return and;}
"or"				        {return or;}
"xor"				        {return xor;}
"test"				      {return test;}
"shl"				        {return shl;}
"shr"				        {return shr;}
"ldr"				        {return ldr;}
"str"				        {return str;}
[ \t\r]                   {;}
r[0-7]|sp|pc|psw    {char* text;if(!strcmp(yytext,"sp"))text="r6";else if(!strcmp(yytext,"pc"))text="r7";else if(!strcmp(yytext,"psw"))text="r8";else text=yytext;yylval.registerr = text; return reg;}
[a-zA-Z_\.][a-zA-Z0-9_\.]*			   {yylval.id = yytext; return identifier;}
(-?([0]|[1-9][0-9]*))                {yylval.num = atoi(yytext); return number;}
([0][x][0-9A-Fa-f]+)                {yylval.num = (int)strtol(yytext, NULL, 0); return number;}
.                      {printf("Unexpected is:[%s]\n",yytext); yyerror ("unexpected character\n");}

%%
int yywrap (void) {return 1;}
