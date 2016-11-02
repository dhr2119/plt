%{ open Ast %}

%token LPAREN RPAREN LBRACE RBRACE SEMI COMMA
%token PLUS MINUS TIMES DIVIDE LBRACKET RBRACKET 
%token ASSIGN EQ NEQ LT LEQ GT GEQ AND OR NOT INC DEC COLON
%token IF ELSE FOR WHILE RETURN MAIN
%token TRUE FALSE
%token INT BOOL VOID STRING MAT NULL
%token <int> LITERAL
%token <string> ID
%token <double> DOUBLE
%token EOF

%nonassoc NOELSE
%nonassoc ELSE
%right ASSIGN
%left OR
%left AND
%left EQ NEQ
%left LT GT LEQ GEQ
%left PLUS MINUS
%left TIMES DIVIDE
%right NOT NEG

%start main
%type <int> main

%%

main: decls EOF { $1 } /* ?? anything else */

decls: /* nothing */ { [], [] }
  | decls vdecl        { ($2 :: fst $1), snd $1 }
  | decls fdecl        { fst $1, ($2 :: snd $1) }

fdecl:
  typ ID LPAREN formals_opt RPAREN LBRACE vdecl_list stmt_list RBRACE
    { { typ = $1; fname = $2; formals = $4; 
      locals = List.rev $7; body = List.rev $8 } } /* change this ?? */

formals_opt: /* nothing */ { [] }
           | formal_list   { List.rev $1 }

formal_list: 
            typ ID { [($1,$2)] }
           | formal_list COMMA typ ID { ($3,$4) :: $1 }

typ: INT    { Int }
   | BOOL   { Bool }
   | VOID   { Void }
   | DOUBLE { Double }
   | STRING { String }
   | NULL   { Null }
   | MAT    { Mat }  /* or */

/*
mdecl_list:  nothing  { [] }
     | mdecl_list mdecl { $2 :: $1 }
*/

mdecl: 
     | typ LBRACKET LITERAL RBRACKET ID SEMI                { ($1, $2) }
     | typ LBRACKET LITERAL COMMA LITERAL RBRACKET ID SEMI  { ($1, $2, $3) }


/* ??
matrix_type:
  primitive LBRACK INTLIT COLON INTLIT RBRACK { MatrixType(DataType($1), $3, $5) }
*/

vdecl_list: /* nothing */ { [] }
          | vdecl_list vdecl { $2 :: $1 }

vdecl: typ ID SEMI { ($1, $2) }

stmt_list:
    /* nothing */ { [] }
  | stmt_list stmt { $2 :: $1 }

stmt:
    expr SEMI                                               { Expr $1 }
  | RETURN SEMI                                             { Return Noexpr }
  | RETURN expr SEMI                                        { Return $2 }
  | LBRACE stmt_list RBRACE                                 { Block(List.rev $2) }
  | IF LPAREN expr RPAREN stmt %prec NOELSE                 { If($3, $5, Block([])) }
  | IF LPAREN expr RPAREN stmt ELSE stmt                    { If($3, $5, $7) }
  | FOR LPAREN expr_opt SEMI expr SEMI expr_opt RPAREN stmt { For($3, $5, $7, $9) }
  | WHILE LPAREN expr RPAREN stmt                           { While($3, $5) }

expr:
    LITERAL                                         { Literal($1) }
  | DOUBLE                                          { Double($1) } /* ?? */
  | MAT                                             { Mat($1) }    /* ?? */
  | TRUE                                            { BoolLit(true) }
  | FALSE                                           { BoolLit(false) }
  | ID                                              { Id($1) }
  | expr PLUS expr                                  { Binop($1, Add, $3) }
  | expr MINUS expr                                 { Binop($1, Sub, $3) }
  | expr TIMES expr                                 { Binop($1, Mult, $3) }
  | expr DIVIDE expr                                { Binop($1, Div, $3) }
  | expr EQ expr                                    { Binop($1, Equal, $3) }
  | expr NEQ expr                                   { Binop($1, Neq, $3) }
  | expr LT expr                                    { Binop($1, Less, $3) }
  | expr LEQ expr                                   { Binop($1, Leq, $3) }
  | expr GT expr                                    { Binop($1, Greater, $3) }
  | expr GEQ expr                                   { Binop($1, Geq, $3) }
  | expr AND expr                                   { Binop($1, And, $3) }
  | expr OR expr                                    { Binop($1, Or, $3) }
  | expr INC                                        { Unop($1, Inc)} /* add one in ast */
  | INC expr /* specify in AST */                   { Unop(Dec, $1)} /* add one in ast */
  | DEC expr                                        { Unop(Dec, $1)} /* add one in ast */
  | expr DEC                                        { Binop($1, Dec)} /* minus one in ast */
  | LBRACKET expr COLON expr RBRACKET               { Call($1, Colon, $3) }
  /* | LBRACKET expr COLON expr COLON expr RBRACKET { Binop($1, Colon, $3, Colon, $5) } */
  | MINUS expr %prec NEG                            { Unop(Neg, $2) }
  | NOT expr                                        { Unop(Not, $2) }
  | ID ASSIGN expr                                  { Assign($1, $3) }
  | LPAREN expr RPAREN                              { $2 }
  | ID LPAREN actuals_opt RPAREN                    { Call($1, $3) }

expr_opt:
    /* nothing */ { Noexpr }
  | expr { $1 }

actuals_opt:
    /* nothing */ { [] }
  | actuals_list { List.rev $1 }

actuals_list:
    expr { [$1] }
  | actuals_list COMMA expr { $3 :: $1 }

array_literal:
    LITERAL                      { [$1] }
  | array_literal COMMA literals { $3 :: $1 } 