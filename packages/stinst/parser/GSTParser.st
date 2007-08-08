"======================================================================
|
|   GNU Smalltalk syntax parser
|
|
 ======================================================================"


"======================================================================
|
| Copyright 2007 Free Software Foundation, Inc.
| Written by Daniele Sciascia.
|
| This file is part of the GNU Smalltalk class library.
|
| The GNU Smalltalk class library is free software; you can redistribute it
| and/or modify it under the terms of the GNU Lesser General Public License
| as published by the Free Software Foundation; either version 2.1, or (at
| your option) any later version.
| 
| The GNU Smalltalk class library is distributed in the hope that it will be
| useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
| MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser
| General Public License for more details.
| 
| You should have received a copy of the GNU Lesser General Public License
| along with the GNU Smalltalk class library; see the file COPYING.LIB.
| If not, write to the Free Software Foundation, 59 Temple Place - Suite
| 330, Boston, MA 02110-1301, USA.  
|
 ======================================================================"

STInST.STFileInParser subclass: GSTFileInParser [
    | class |

    parseStatements [
        | returnPosition statements node |

        (currentToken isSpecial and: [currentToken value == $!]) 
	   ifTrue: [ ^RBSequenceNode statements: #() ].

        statements := OrderedCollection new.

        (currentToken isSpecial and: [currentToken value == $^]) 
            ifTrue: [returnPosition := currentToken start.  
                     self step.
                     node := RBReturnNode return: returnPosition value: self parseAssignment.
                     self addCommentsTo: node.
                     statements add: node]
            ifFalse: [node := self parseAssignment.
                      self addCommentsTo: node.
                      statements add: node].

        (currentToken isSpecial and: [self skipToken: $[])
            ifTrue: [self parseDeclaration: node. ^nil].

        ^RBSequenceNode statements: statements
    ]

    parseDeclaration: node [
        node isMessage ifTrue: [
            (node selectorParts first value = 'subclass:')
                ifTrue: [self parseClass: node. ^self].
                
            ((node receiver name = 'Namespace') 
                and: [node selectorParts first value = 'current:' ])
                    ifTrue: [self parseNamespace: node. ^self].
            
            (node selectorParts first value = 'extend')
                ifTrue: [self parseClassExtension: node. ^self]].
        
        node isVariable 
            ifTrue: [(node name = 'Eval') 
                        ifTrue: [self parseEval. ^self]].
        
        self parserError: 'expected Eval, Namespace or class definition'
    ]
    
    parseEval [
        | stmts |
        stmts := self parseStatements: false.
        self skipExpectedToken: $].
        self evaluate: stmts.
    ]
    
    parseNamespace: node [   
        | namespace fullNamespace |
        namespace := RBVariableNode
	    named: self driver currentNamespace name asString.
        fullNamespace := RBVariableNode
	    named: (self driver currentNamespace nameIn: Smalltalk).

        self evaluateMessageOn: namespace
             selector: #addSubspace:
             argument: node arguments first name asSymbol.
           
        self evaluateStatement: node.       
        self parseSmalltalk.
        self skipExpectedToken: $].

        "restore previous namespace"
        node parent: nil.
        node arguments: { fullNamespace }.
        self evaluateStatement: node
    ]
    
    parseClassExtension: node [
        class := node receiver.
        self parseClassBody.
        class := nil
    ]
    
    parseClass: node [ 
        self evaluateMessageOn: (node receiver)
             selector: #subclass:
             argument: (node arguments first name asSymbol).
             
        class := node arguments first.
        self parseClassBody.
        class := nil.
    ]
    
    parseClassBody [
        [ self skipToken: $] ]
            whileFalse: [ self parseClassBodyElement ]
    ]
    
    parseClassBodyElement [
        | node classNode |
        
        "look for class tag"
        (currentToken value = #< and: [self nextToken isKeyword])
            ifTrue: [self parseClassTag. ^self].
        
        "look for class variable"
        (currentToken isIdentifier and: [self nextToken isAssignment])
            ifTrue: [self parseClassVariable. ^self].
            
        "class side"
        ((currentToken isIdentifier 
            and: [self nextToken isIdentifier])
            and: [self nextToken value = 'class'])
                ifTrue: [classNode := RBVariableNode identifierToken: currentToken.
                         self step.
    
                         (classNode = class)
                            ifTrue: ["look for class method"
                                     (self nextToken value = #>>)
                                        ifTrue: [self step. self step.
                                                 self parseMethodSourceOn: (self makeClassOf: classNode). 
                                                 ^self ].
                                            
                                     "look for metaclass"
                                     (self nextToken value = $[)
                                        ifTrue: [self parseMetaclass.
                                                 ^self ].
                                        
                                     self parserError: 'invalid class body element'].
                          
                         "look for overriding class method"
                         self step.
                         (currentToken value = #>>)
                            ifTrue: ["TODO: check that classNode is a superclass of the current class"
                                     self step.
                                     self parseMethodSourceOn: (self makeClassOf: classNode).
                                     ^self]. 
                          
                          self parserError: 'invalid class body element' ].
                        
        "look for overriding method"
        (currentToken isIdentifier and: [self nextToken value = #>>])
            ifTrue: ["check that classNode is a superclass of the current class!!!"    
                     classNode := RBVariableNode identifierToken: currentToken.
                     self step. self step.
                     self parseMethodSourceOn: classNode.
                     ^self].
               
        node := self parseMessagePattern.
        
        "look for method"
        (self skipToken: $[)
            ifTrue: [self parseMethodSource: node. ^self].
        
        "look for instance variables"
        (node selectorParts first value = #|)
            ifTrue: [self parseInstanceVariables: node. ^self].
            
        self parserError: 'invalid class body element'
    ]
    
    parseClassTag [
        | selector argument stmt |
        
        self skipExpectedToken: #<.
        
        (currentToken isKeyword)
            ifTrue: [selector := currentToken value asSymbol. self step]
            ifFalse: [self parserError: 'expected keyword'].
        
        argument := self parsePrimitiveObject.
        self skipExpectedToken: #>.
        
        argument isVariable
            ifTrue: [stmt := RBMessageNode
    	                     receiver: class
    	                     selector: selector
    	                     arguments: { argument }.
                     self evaluateStatement: stmt]
            ifFalse: [self evaluateMessageOn: class
                           selector: selector
                           argument: argument token value]
    ]
    
    parseClassVariable [ 
        | node stmt name |
        
        node := self parseAssignment.
        node isAssignment
            ifFalse: [self parserError: 'expected assignment'].
        
        self skipExpectedToken: $. .

        name := RBLiteralNode value: (node variable name asSymbol).
        node := self makeSequenceNode: node.
        node := RBBlockNode body: node.
        
        stmt := RBMessageNode 
                receiver: class
                selector: #addClassVarName:value:
                arguments: { name . node }.

        self evaluateStatement: stmt.
    ]
    
    parseMetaclass [
        | tmpClass |     
        
        self step. self step.
        tmpClass := class.
        class := self makeClassOf: class.
        self parseClassBody.
        class := tmpClass
    ]
    
    parseMethodSource: patternNode [
        self parseMethodSource: patternNode on: class
    ]
    
    parseMethodSourceOn: classNode [
        | patternNode |
        
        patternNode := self parseMessagePattern.
        self skipExpectedToken: $[.
        self parseMethodSource: patternNode on: classNode.
    ]
    
    parseMethodSource: patternNode on: classNode [
        "TODO: parse category tag inside methods"
        | methodNode source start stop |
        
        start := patternNode selectorParts first start - 1.
        methodNode := self parseMethodInto: patternNode.
        stop := currentToken start - 1.
        self skipExpectedToken: $].
        source := scanner stream copyFrom: start to: stop.
        source := MappedCollection collection: source map: (1 - start to: stop).
        methodNode source: source.
        
        self evaluateMessageOn: classNode
             selector: #methodsFor:
             argument: nil.
        
        self compile: methodNode
    ]
    
    parseInstanceVariables: node [
        | vars |
            
        vars := (node arguments at: 1) name.
        [currentToken isIdentifier]
            whileTrue: [vars := vars , ' ' , currentToken value.
        
                        self step ].       
        self skipExpectedToken: #|.
        
        self evaluateMessageOn: class 
             selector: #instanceVariableNames:
             argument: vars.
    ]
    
    evaluateMessageOn: rec selector: sel argument: arg [
        | stmt |
          
        stmt := RBMessageNode
	            receiver: rec
	            selector: sel
	            arguments: { RBLiteralNode value: arg }.
	    	    
        self evaluateStatement: stmt.
    ]
    
    evaluateStatement: node [
        ^self evaluate: (self makeSequenceNode: node).
    ]
    
    makeSequenceNode: stmt [
        | seq |
	seq := RBSequenceNode
            leftBar: nil
            temporaries: #()
            rightBar: nil.
        seq statements: { stmt }.
        seq periods: #().
	^seq
    ]
    
    makeClassOf: node [
        ^RBMessageNode
    	    receiver: node
    	    selector: #class
    	    arguments: #()
    ]

    skipToken: tokenValue [
        (currentToken value = tokenValue)
            ifTrue: [self step. ^true]
            ifFalse: [^false]
    ]
    
    skipExpectedToken: tokenValue [
        (self skipToken: tokenValue)
            ifFalse: [self parserError: ('expected ' , tokenValue asSymbol)]
    ]
]