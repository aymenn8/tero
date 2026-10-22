#!/usr/bin/env python3
"""Synthetic AI provider for bring-your-own-key tests. Speaks OpenAI Responses,
Anthropic Messages and OpenAI-compatible chat completions on localhost.
Every request body is appended to <log> so tests can assert its shape.
Usage: byok_mock_provider.py <port> <log>"""
import json, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT, LOG = int(sys.argv[1]), sys.argv[2]
SOURCE = 'https://www.example-shop.com/keyboard'

def result_for(name):
    return {
        'key_points': {'status': 'ok', 'points': ['First idea', 'Second idea']},
        'extract_tasks': {'status': 'ok', 'tasks': [{'action': 'Send the report', 'owner': None, 'deadline': 'Friday'}]},
        'reply_options': {'status': 'ok', 'intents': ['accept', 'decline', 'clarify']},
        'task_plan': {'status': 'ok', 'items': []},
        'file_names': {'status': 'ok', 'names': [{'id': 'file-0', 'stem': 'orion-invoice'}]},
        'shopping_products': {'summary': 'One quiet keyboard.', 'products': [
            {'name': 'Quiet keyboard', 'price': '80 EUR', 'reason': 'Quiet switches', 'tradeoff': 'Wired', 'url': SOURCE}]},
    }.get(name, {'status': 'ok', 'text': 'This is a quick test.'})

def schema_name(body):
    fmt = (body.get('text') or {}).get('format') or {}
    if fmt.get('name'): return fmt['name']
    rf = body.get('response_format') or {}
    if rf.get('json_schema'): return rf['json_schema']['name']
    tool = body.get('tool_choice')
    if isinstance(tool, dict) and tool.get('name'): return tool['name']
    text = json.dumps(body)
    if 'tradeoff' in text: return 'shopping_products'
    for name in ['shopping_products', 'key_points', 'extract_tasks', 'reply_options', 'file_names', 'task_plan']:
        if name in text: return name
    if 'JSON Schema' in text: return 'correction'
    return None

class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args): pass

    def send_json(self, status, value):
        data = json.dumps(value).encode()
        self.send_response(status); self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)

    def sse(self, events):
        self.send_response(200); self.send_header('Content-Type', 'text/event-stream'); self.end_headers()
        for event in events:
            self.wfile.write(b'data: ' + json.dumps(event).encode() + b'\n\n'); self.wfile.flush()
        self.wfile.write(b'data: [DONE]\n\n')

    def do_GET(self):
        if self.path.endswith('/models'):
            return self.send_json(200, {'data': [{'id': 'mock-small'}, {'id': 'mock-large'}]})
        self.send_json(404, {})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        auth = self.headers.get('Authorization') or self.headers.get('x-api-key') or ''
        with open(LOG, 'a') as log:
            log.write(json.dumps({'path': self.path, 'auth': auth, 'body': body}) + '\n')
        if 'bad' in auth: return self.send_json(401, {'error': 'invalid key'})
        if self.path.endswith('/systemone'):
            def answer(id):
                level = 2 if id == 'fix' else 1
                return {'type': 'score', 'score': level, 'confidence': 0.9, 'probabilities': {str(n): 1 if n == level else 0 for n in range(4)}}
            model = 'other-model' if 'wrongmodel' in auth else body.get('model')
            return self.send_json(200, {'model': model, 'answers': {id: answer(id) for id in body['questions']},
                                        'usage': {'input_tokens': 500, 'output_tokens': 10}})
        name = schema_name(body)
        # Simulate a provider that rejects strict JSON schema output.
        if body.get('model') == 'no-schema' and (body.get('response_format') or {}).get('type') == 'json_schema':
            return self.send_json(400, {'error': 'json_schema unsupported'})
        text = json.dumps(result_for(name)) if name else 'The answer, according to a source.'
        searched = bool(body.get('tools') and any(t.get('type', '').startswith('web_search') for t in body['tools'])) or bool(body.get('plugins'))
        stream = body.get('stream')
        if self.path.endswith('/responses'):
            content = {'type': 'output_text', 'text': text,
                       'annotations': [{'type': 'url_citation', 'url': SOURCE, 'title': 'Example shop', 'start_index': 0, 'end_index': 0}] if searched else []}
            output = ([{'type': 'web_search_call', 'action': {'sources': [{'type': 'url', 'url': SOURCE}]}}] if searched else []) + \
                     [{'type': 'message', 'content': [content]}]
            response = {'status': 'completed', 'output': output}
            if stream:
                return self.sse([{'type': 'response.output_text.delta', 'delta': text[:12]},
                                 {'type': 'response.output_text.delta', 'delta': text[12:]},
                                 {'type': 'response.completed', 'response': response}])
            return self.send_json(200, response)
        if self.path.endswith('/messages'):
            forced = isinstance(body.get('tool_choice'), dict)
            if stream:
                kind = 'partial_json' if forced else 'text'
                return self.sse([{'type': 'content_block_delta', 'delta': {kind: text[:12]}},
                                 {'type': 'content_block_delta', 'delta': {kind: text[12:]}},
                                 {'type': 'message_delta', 'delta': {'stop_reason': 'end_turn'}}, {'type': 'message_stop'}])
            blocks = [{'type': 'tool_use', 'name': name, 'input': json.loads(text)}] if forced else []
            if searched:
                blocks += [{'type': 'server_tool_use'}, {'type': 'web_search_tool_result', 'content': [{'type': 'web_search_result', 'url': SOURCE, 'title': 'Example shop'}]}]
            if not forced:
                blocks.append({'type': 'text', 'text': text, 'citations': [{'type': 'web_search_result_location', 'url': SOURCE}] if searched else []})
            return self.send_json(200, {'content': blocks, 'stop_reason': 'tool_use' if forced else 'end_turn'})
        if self.path.endswith('/chat/completions'):
            if stream:
                return self.sse([{'choices': [{'delta': {'content': text[:12]}}]}, {'choices': [{'delta': {'content': text[12:]}, 'finish_reason': 'stop'}]}])
            message = {'content': '```json\n' + text + '\n```' if body.get('model') == 'no-schema' else text}
            if searched: message['annotations'] = [{'type': 'url_citation', 'url_citation': {'url': SOURCE, 'title': 'Example shop'}}]
            return self.send_json(200, {'choices': [{'message': message, 'finish_reason': 'stop'}]})
        self.send_json(404, {})

ThreadingHTTPServer(('127.0.0.1', PORT), Handler).serve_forever()
