import ceylon.file { Writer }
import ceylon.collection { MutableList, LinkedList }
import org.antlr.runtime { AntrlToken=Token, TokenStream }
import com.redhat.ceylon.compiler.typechecker.parser { CeylonLexer { lineComment=\iLINE_COMMENT, multiComment=\iMULTI_COMMENT, ws=\iWS } }
import ceylon.formatter.options { FormattingOptions }

"The maximum value that is safe to use as [[FormattingWriter.writeToken]]’s `wantsSpace[Before|After]` argument.
 
 Using a greater value risks inverting the intended result due to overflow."
Integer maxDesire = runtime.maxIntegerValue / 2;
"The minimum value that is safe to use as [[FormattingWriter.writeToken]]’s `wantsSpace[Before|After]` argument.
 
 Using a smaller value risks inverting the intended result due to overflow."
Integer minDesire = runtime.minIntegerValue / 2;

"Used in [[FormattingWriter.fastForward]]."
abstract class Stop() of stopAndConsume|stopAndDontConsume { shared formal Boolean consume; }
object stopAndConsume extends Stop() { consume = true; }
object stopAndDontConsume extends Stop() { consume = false; }

"Writes out tokens, respecting certain indentation settings and a maximum line width.
 
 Each token written with the [[writeToken]] method is stored in a buffer. As soon as enough tokens
 are present to decide where a line break should occur, the entire line is written out to the
 underlying [[writer]] and the tokens are removed from the buffer. This can also be forced at any
 time with the [[nextLine]] method.
 
 Indentation stacks over the tokens: Each token can specify by how many levels the tokens following
 it should be indented. Such a token opens a [[FormattingContext]], which is then returned by
 `writeToken`. The context can later be closed with another token by passing it to the `writeToken`
 method, which will remove the context and all the contexts on top of it from the context stack.
 The indentation level of a line is the sum of the indentation levels of all contexts on the stack.
 
 You can get a `FormattingContext` not associated with any tokens from the [[acquireContext]]
 method; this is useful if you only have a closing token, but no opening token: for example, the
 semicolon terminating a statement should clearly close some context, but there is no special
 token which opens that context."
class FormattingWriter(TokenStream tokens, Writer writer, FormattingOptions options) {
    
    shared interface FormattingContext {
        shared formal Integer postIndent;
    }
      
    interface Element of OpeningElement|ClosingElement {
        shared formal FormattingContext context;
    }
    interface OpeningElement satisfies Element {}
    interface ClosingElement satisfies Element {}
    
    abstract class Token(text, postIndent, wantsSpaceBefore, wantsSpaceAfter)
        of OpeningToken|ClosingToken {
        
        shared default String text;
        shared default Integer? postIndent;
        shared default Integer wantsSpaceBefore;
        shared default Integer wantsSpaceAfter;
        
        shared actual String string => text;
    }
    
    class NoToken() satisfies OpeningElement {
        shared actual object context satisfies FormattingContext {
            postIndent = 0;
        }
    }
    
    class OpeningToken(text, postIndent, wantsSpaceBefore, wantsSpaceAfter)
        extends Token(text, postIndent, wantsSpaceBefore, wantsSpaceAfter)
        satisfies OpeningElement {
        
        shared actual String text;
        shared actual Integer? postIndent;
        shared actual Integer wantsSpaceBefore;
        shared actual Integer wantsSpaceAfter;
        shared actual object context satisfies FormattingContext {
            postIndent = outer.postIndent else 0;
        }
    }
    class ClosingToken(text, postIndent, wantsSpaceBefore, wantsSpaceAfter, context)
            extends Token(text, postIndent, wantsSpaceBefore, wantsSpaceAfter)
            satisfies ClosingElement {
        
        shared actual String text;
        shared actual Integer? postIndent;
        shared actual Integer wantsSpaceBefore;
        shared actual Integer wantsSpaceAfter;
        shared actual FormattingContext context;
    }
    
    class LineBreak() {}
    
    alias QueueElement => NoToken|LineBreak|Token;
    
    "The `tokenQueue` holds all tokens that have not yet been written."
    MutableList<QueueElement> tokenQueue = LinkedList<QueueElement>();
    "The `tokenStack` holds all tokens that have been written, but whose context has not yet been closed."
    MutableList<FormattingContext> tokenStack = LinkedList<FormattingContext>();
    "The `indentStack` holds only the tokens from [[tokenStack]] that were written at the end of a line,
     i. e. whose `postIndent` is actually effective."
    MutableList<FormattingContext> indentStack = LinkedList<FormattingContext>();
    
    "Remembers if anything was ever enqueued."
    variable Boolean isEmpty = true;
    
    "Write a token, respecting [[FormattingOptions.maxLineLength]] and non-AST tokens (comments).
     
     If [[token]] is a [[Token]], fast-forward the token stream until `token` is reached, writing out
     any comment tokens, then write out `token`’s text as described below.
     
     If `token` is a `String`, put it into the token queue and check if a line can be written out.
     
     This method should always be used to write any tokens."
    shared FormattingContext? writeToken(
        AntrlToken|String token,
        Integer? indentBefore,
        Integer? postIndent,
        Integer wantsSpaceBefore,
        Integer wantsSpaceAfter,
        FormattingContext? context = null) {
        
        String tokenString;
        if (is AntrlToken token) {
            fastForward((AntrlToken current) {
                if (current.type == lineComment || current.type == multiComment) {
                    SequenceBuilder<QueueElement|Stop> ret = SequenceBuilder<QueueElement|Stop>();
                    
                    Boolean multiLine = current.type == multiComment && current.text.contains('\n');
                    if (multiLine && !isEmpty) {
                        // multi-line comments start and end on their own line
                        ret.append(LineBreak());
                    }
                    // now we need to produce the following pattern: for each line in the comment,
                    // line, linebreak, line, linebreak, ..., line.
                    // notice how there’s no linebreak after the last line, which is why this gets
                    // a little ugly...
                    String? firstLine = current.text
                            .split((Character c) => c == '\n')
                            .first;
                    assert (exists firstLine);
                    ret.append(OpeningToken(
                        firstLine.trimTrailing((Character c) => c == '\r'),
                        0, maxDesire, maxDesire));
                    ret.appendAll({
                        for (line in current.text
                                .split((Character c) => c == '\n')
                                .rest
                                .filter((String elem) => !elem.empty)
                                .map((String l) => l.trimTrailing((Character c) => c == '\r')))
                            for (element in {LineBreak(), OpeningToken(line, 0, maxDesire, maxDesire)})
                                element
                    });
                    if (multiLine) {
                        ret.append(LineBreak());
                    }
                    
                    return ret.sequence;
                } else if (current.type == ws) {
                    return empty;
                } else if (current.text == token.text) {
                    return {stopAndConsume}; // end fast-forwarding
                } else {
                    throw Exception("Unexpected token '``current.text``'");
                }
            });
            tokenString = token.text;
        } else {
            assert (is String token); // the typechecker can't figure that out (yet), see ceylon-spec#74
            tokenString = token;
        }
        FormattingContext? ret;
        Token t;
        if (exists context) {
            t = ClosingToken(tokenString, postIndent, wantsSpaceBefore, wantsSpaceAfter, context);
            ret = null;
        } else {
            t = OpeningToken(tokenString, postIndent, wantsSpaceBefore, wantsSpaceAfter);
            assert (is OpeningToken t); // ...yeah
            ret = t.context;
        }
        tokenQueue.add(t);
        isEmpty = false;
        writeLines();
        return ret;
    }
    
    "Fast-forward the token stream until the next token contains a line break or isn't hidden, writing out any comment tokens,
     then write a line break.
     
     This is needed to keep a line comment at the end of a line instead of putting it into the next line."
    shared void nextLine() {
        fastForward((AntrlToken current) {
            if (current.type == lineComment || current.type == multiComment || current.type == ws) {
                if (current.type == ws) {
                    return empty;
                }
                
                SequenceBuilder<QueueElement|Stop> ret = SequenceBuilder<QueueElement|Stop>();
                
                Boolean multiLine = current.type == multiComment && current.text.contains('\n');
                if (multiLine) {
                    // multi-line comments start and end on their own line
                    ret.append(LineBreak());
                }                
                ret.appendAll({
                    for (line in current.text
                            .split((Character ch) => ch == '\n')
                            .filter((String elem) => !elem.empty))
                        OpeningToken(line, 0, 100, current.type == multiComment then 100 else 0)
                });                
                if (multiLine) {
                    ret.append(LineBreak());
                }
                ret.append(stopAndConsume);
                
                return ret.sequence;
            } else {
                return {LineBreak(), stopAndDontConsume}; // end fast-forwarding
            }
        });
        writeLines();
    }
    
    shared FormattingContext acquireContext() {
        value noToken = NoToken();
        tokenQueue.add(noToken);
        return noToken.context;
    }
    
    "Write a line if there are enough tokens enqueued to determine where the next line break should occur.
     
     Returns `true` if a line was written, `false` otherwise.
     
     As the queue can contain enough tokens for more than one line, you’ll typically want to call
     [[writeLines]] instead."
    Boolean tryNextLine() {
        // TODO implement a good line break strategy here
        Integer? i = tokenQueue.indexes(function (FormattingWriter.QueueElement element) {
           if (is LineBreak element) {
               return true;
           }
           return false;
        }).first;
        if (exists i) {
            writeLine(i);
            return true;
        }
        return false;
    }
    
    "Write out lines as long as there are enough tokens enqueued to determine where the next
     line break should occur."
    void writeLines() {
        while(tryNextLine()) {}
    }
    
    "Write `i + 1` tokens from the queue, followed by a line break.
     
     1. Take elements `0..i` from the queue (making the formerly `i + 1`<sup>th</sup> token the new first token)
     2. Determine the first and last token in that range
     3. If the first token is a [[ClosingToken]], [[close|closeContext]] its context
     4. Write indentation – the sum of all `postIndent`s on the [[indentStack]]
     5. [[write]] the elements (write the first token directly)
     7. Write a line break
     8. If the last token is an [[OpeningToken]], push its context onto the `indentStack`
     
     (Note that there may not appear any line breaks before token `i`.)"
    void writeLine(Integer i) {
        Boolean(QueueElement) isToken = function (QueueElement elem) {
            if (is Token elem) {
                return true;
            }
            return false;
        };
        
        QueueElement? firstToken = tokenQueue[0..i].find(isToken);
        QueueElement? lastToken = tokenQueue[0..i].findLast(isToken);
        
        if (is ClosingToken firstToken) {
            closeContext(firstToken.context);
        }
        
        Integer indentLevel = indentStack.fold(0,
            (Integer partial, FormattingContext elem) => partial + elem.postIndent);
        writer.write(options.indentMode.indent(indentLevel));
        
        variable Token? previousToken = null;
        for (c in 0..i) {
            QueueElement? removed = tokenQueue.removeFirst();
            assert (exists removed);
            if (is Token currentToken = removed) {
                if (exists p = previousToken, p.wantsSpaceAfter + currentToken.wantsSpaceBefore >= 0) {
                    writer.write(" ");
                }
                if (exists firstToken, currentToken == firstToken, is ClosingToken currentToken) {
                    // don’t attempt to close this context, we already did that
                    writer.write(currentToken.text);
                } else {
                    write(currentToken);
                }
                previousToken = currentToken;
            } else if (is NoToken removed) {
                tokenStack.add(removed.context);
            }
        }
        
        writer.writeLine();
        
        if (is OpeningToken lastToken) {
            indentStack.add(lastToken.context);
        }
    }
    
    "Write a token.
     
     1. Write the token’s text
     2. Context handling:
         1. If [[token]] is a [[OpeningToken]], push its context onto the [[tokenStack]];
         2. if it’s a [[ClosingToken]], [[closeContext]] its context."
    void write(Token token) {
        writer.write(token.text);
        
        if (is OpeningToken token) {
            tokenStack.add(token.context);
        } else if (is ClosingToken token) {
            closeContext(token.context);
        }
    }
    
    "Close a [[FormattingContext]].
     
     Remove [[context]] and all its successors from [[tokenStack]] and [[indentStack]]."
    void closeContext(FormattingContext context) {
        Integer? indexOf = tokenStack.indexes((FormattingContext element) => element == context).first;
        assert (exists indexOf);
        for (FormattingContext c in tokenStack.terminal(tokenStack.size - indexOf)) {
            variable Boolean contains = false;
            while (indentStack.contains(c)) {
                contains = true;
                indentStack.removeLast();
            }
            if (contains) {
                break;
            }
        }
        for(c in indexOf..tokenStack.size-1) {
            tokenStack.removeLast();
        }
    }
    
    "Fast-forward the token stream.
     
     Each token is sent to [[tokenConsumer]], and all non-null [[QueueElement]]s in the
     return value are added to the queue. A [[Stop]] element will stop fast-forwarding;
     its [[consume|Stop.consume]] will determine if the last token is
     [[consumed|TokenStream.consume]] or not."
    void fastForward({QueueElement|Stop*}(AntrlToken) tokenConsumer) {
        variable Integer i = tokens.index();
        variable {QueueElement|Stop*} resultTokens = tokenConsumer(tokens.get(i));
        variable Boolean hadStop = false;
        while (!hadStop) {
            for (QueueElement|Stop element in resultTokens) {
                if (is QueueElement element) {
                    tokenQueue.add(element);
                } else {
                    assert (is Stop element);
                    hadStop = true;
                    if (element.consume) {
                        tokens.consume();
                    }
                    break;
                }
            } else {
                tokens.consume();
                resultTokens = tokenConsumer(tokens.get(++i));
            }
        }
    }
    
    "Enqueue a line break if the last queue element isn’t a line break, then flush the queue."
    shared void close() {
        if (!isEmpty) {
            QueueElement? lastElement = tokenQueue.findLast(function (QueueElement elem) {
                if (is NoToken elem) {
                    return false;
                }
                return true;
            });
            if (exists lastElement, !is LineBreak lastElement) {
                tokenQueue.add(LineBreak());
            }
            writeLines();
        }
    }
}