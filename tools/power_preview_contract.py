"""Compile the frozen tooltip arithmetic to data, never executable Godot code."""
import ast
import re
import math

MARKER = re.compile(r"%\$(.*?)%\$(%?)", re.S)

def expression(text):
    def node(n):
        if isinstance(n, ast.Constant) and isinstance(n.value, (str, int, float)):
            return ['value', n.value]
        if isinstance(n, ast.Name) and n.id in ('level', 'tdmg', 'tcd'):
            return ['context', n.id]
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id == 'T' and len(n.args) == 1 and not n.keywords and isinstance(n.args[0], ast.Constant) and isinstance(n.args[0].value, str):
            return ['template', n.args[0].value]
        if isinstance(n, ast.Attribute) and not n.attr.startswith('_'):
            return ['field', node(n.value), n.attr]
        if isinstance(n, ast.Subscript):
            return ['index', node(n.value), node(n.slice)]
        if isinstance(n, ast.UnaryOp) and isinstance(n.op, ast.USub):
            return ['negate', node(n.operand)]
        if isinstance(n, ast.BinOp) and type(n.op) in (ast.Add, ast.Sub, ast.Mult, ast.Div):
            return [{ast.Add:'+', ast.Sub:'-', ast.Mult:'*', ast.Div:'/'}[type(n.op)], node(n.left), node(n.right)]
        raise ValueError(f'Unsupported tooltip arithmetic: {text}')
    return node(ast.parse(text.strip(), mode='eval').body)

def compile_text(text):
    tokens = []; end = 0
    for match in MARKER.finditer(text):
        if match.start() > end: tokens.append(text[end:match.start()])
        tokens.append({'expression': expression(match[1]), 'percent': bool(match[2])})
        end = match.end()
    if end < len(text): tokens.append(text[end:])
    if any(isinstance(t, str) and '%$' in t for t in tokens): raise ValueError(f'Unexpanded tooltip expression: {text}')
    return tokens

def evaluate(node, templates, context, depth=0):
    if depth>32 or not isinstance(node,list) or not node:raise ValueError('Invalid tooltip descriptor')
    op=node[0]
    if op=='value' and len(node)==2 and type(node[1]) in (int,float,str):return node[1]
    if op=='context' and len(node)==2 and node[1] in context:return context[node[1]]
    if op=='template' and len(node)==2:return templates[node[1]]
    if op=='field' and len(node)==3 and isinstance(node[2],str) and not node[2].startswith('_'):
        return evaluate(node[1],templates,context,depth+1)[node[2]]
    if op=='index' and len(node)==3:
        index=evaluate(node[2],templates,context,depth+1)
        if not isinstance(index,(int,float)) or int(index)!=index or index<1:raise ValueError('Invalid tooltip array index')
        return evaluate(node[1],templates,context,depth+1)[int(index)-1]
    if op=='negate' and len(node)==2:return -evaluate(node[1],templates,context,depth+1)
    if op in ('+','-','*','/') and len(node)==3:
        a=evaluate(node[1],templates,context,depth+1);b=evaluate(node[2],templates,context,depth+1)
        return {'+':lambda:a+b,'-':lambda:a-b,'*':lambda:a*b,'/':lambda:a/b}[op]()
    raise ValueError('Unsupported tooltip descriptor: '+str(op))

def prepare_ui(data):
    ui = data['ui']; ui['power_previews'] = {}
    for items in ui['tower_menus'].values():
        for item in items:
            if 'tt_list' not in item: continue
            ui['power_previews'][item['action_arg']] = [
                {'title': ui['strings'][entry['tt_title']], 'tokens': compile_text(ui['strings'][entry['tt_desc']])}
                for entry in item['tt_list']]
    validate_ui(data)

def validate_ui(data):
    ui = data['ui']; strings = ui['strings']
    for notice in ui['notifications'].values():
        prefixes = [notice['prefix']] if notice.get('layout') == 'N_TOWER' else notice.get('prefixes', []) if notice.get('layout') == 'N_TOWER_2' else []
        for prefix in prefixes:
            for suffix in ('_NAME', '_EXTRA'):
                key = prefix + suffix
                if not strings.get(key) or strings[key] == key or '%$' in strings[key]: raise ValueError(f'Missing or unexpanded tower notification text: {key}')
        for subtitle in notice.get('subs', [notice['sub']] if 'sub' in notice else []):
            if not strings.get(subtitle): raise ValueError(f'Missing tower subtitle: {subtitle}')
    for power, rows in ui.get('power_descriptions', {}).items():
        if any('%$' in row for row in rows): raise ValueError(f'Unexpanded power: {power}')
    for items in ui['tower_menus'].values():
        for item in items:
            if 'tt_list' in item and len(ui.get('power_previews', {}).get(item['action_arg'], [])) != len(item['tt_list']): raise ValueError(f'Missing power preview: {item["action_arg"]}')
    for power,rows in ui.get('power_previews',{}).items():
        for level,row in enumerate(rows,1):
            if not row.get('title') or '%$' in row['title']:raise ValueError('Missing preview title: '+power)
            for token in row['tokens']:
                if isinstance(token,str):
                    if '%$' in token:raise ValueError('Unexpanded preview: '+power)
                    continue
                try:
                    value=evaluate(token['expression'],data['templates'],{'level':level,'tdmg':1,'tcd':1})
                    assert type(token['percent']) is bool and type(value) in (int,float) and math.isfinite(value)
                except (KeyError,IndexError,TypeError,ValueError,AssertionError,ZeroDivisionError) as error:
                    raise ValueError(f'Invalid power preview dependency: {power}/{level}: {error}') from error
