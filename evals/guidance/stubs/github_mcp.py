#!/usr/bin/env python3
"""GitHub MCP stand-in for the mapping-table case (stdio, newline-delimited).

Tool names and the arguments that matter mirror the real server. Issues come
from a state file; `search_issues` reads a stale index, as GitHub's does for
the first minutes of an issue's life. Every call is logged to
<run>/logs/mcp.log as one JSON object per line.
"""
import json
import os
import sys

ROOT = os.environ["RUN_ROOT"]
STATE = os.path.join(ROOT, "mcp-state.json")
LOG = os.path.join(ROOT, "logs", "mcp.log")

REPO = {"owner": {"type": "string"}, "repo": {"type": "string"}}


def tool(name, description, props, required):
    return {"name": name, "description": description,
            "inputSchema": {"type": "object", "properties": {**REPO, **props},
                            "required": ["owner", "repo", *required]}}


NUM = {"type": "number"}
STR = {"type": "string"}
TOOLS = [
    tool("list_issues", "List issues in a GitHub repository.",
         {"state": {"type": "string", "enum": ["OPEN", "CLOSED"]},
          "labels": {"type": "array", "items": STR},
          "fields": {"type": "array", "items": STR},
          "perPage": NUM, "after": STR}, []),
    {"name": "search_issues",
     "description": "Search for issues in GitHub repositories using issues "
                    "search syntax.",
     "inputSchema": {"type": "object",
                     "properties": {"query": STR, "owner": STR, "repo": STR},
                     "required": ["query"]}},
    tool("issue_read", "Get information about a specific issue.",
         {"method": {"type": "string",
                     "enum": ["get", "get_comments", "get_sub_issues",
                              "get_parent", "get_labels"]},
          "issue_number": NUM}, ["method", "issue_number"]),
    tool("issue_write", "Create a new or update an existing issue.",
         {"method": {"type": "string", "enum": ["create", "update"]},
          "issue_number": NUM, "title": STR, "body": STR,
          "labels": {"type": "array", "items": STR},
          "state": {"type": "string", "enum": ["open", "closed"]},
          "parent_issue_number": NUM}, ["method"]),
    tool("sub_issue_write", "Add a sub-issue to a parent issue. sub_issue_id "
         "is the issue's ID, which is not its number.",
         {"method": {"type": "string",
                     "enum": ["add", "remove", "reprioritize"]},
          "issue_number": NUM, "sub_issue_id": NUM,
          "replace_parent": {"type": "boolean"}},
         ["method", "issue_number", "sub_issue_id"]),
    tool("add_issue_comment", "Add a comment to an issue.",
         {"issue_number": NUM, "body": STR}, ["issue_number", "body"]),
    tool("list_pull_requests", "List pull requests in a GitHub repository.",
         {"state": {"type": "string", "enum": ["open", "closed", "all"]},
          "fields": {"type": "array", "items": STR}}, []),
]


def load():
    with open(STATE) as fh:
        return json.load(fh)


def save(state):
    with open(STATE, "w") as fh:
        json.dump(state, fh)


def brief(issue, fields=None):
    keys = fields or ["number", "id", "title", "state", "labels", "created_at",
                      "parent"]
    return {k: issue.get(k) for k in keys if k in issue or k == "parent"}


def call(name, args):
    state = load()
    issues = state["issues"]
    by_number = {i["number"]: i for i in issues}
    if name == "list_issues":
        want = (args.get("state") or "OPEN").lower()
        rows = [i for i in issues if i["state"] == want
                and all(l in i["labels"] for l in args.get("labels") or [])]
        rows.sort(key=lambda i: -i["number"])
        return {"issues": [brief(i, args.get("fields")) for i in rows],
                "pageInfo": {"hasNextPage": False, "endCursor": None},
                "totalCount": len(rows)}
    if name == "search_issues":
        words = [w.lower() for w in args.get("query", "").split()
                 if ":" not in w and w.lower() not in ("in", "or", "and")]
        hits = [i for i in issues if i.get("indexed", True)
                and any(w.strip('"') in i["title"].lower() for w in words)]
        return {"total_count": len(hits), "incomplete_results": False,
                "items": [brief(i) for i in hits]}
    if name == "issue_read":
        issue = by_number.get(int(args["issue_number"]))
        if issue is None:
            raise ValueError("issue not found")
        if args["method"] == "get_sub_issues":
            return [brief(i) for i in issues
                    if i.get("parent") == issue["number"]]
        if args["method"] == "get_parent":
            return brief(by_number[issue["parent"]]) if issue.get("parent") else None
        if args["method"] == "get_labels":
            return issue["labels"]
        if args["method"] == "get_comments":
            return []
        return {**brief(issue), "body": issue.get("body", "")}
    if name == "issue_write":
        if args["method"] == "create":
            number = max(by_number) + 1
            issue = {"number": number, "id": 1000 + number,
                     "title": args.get("title", ""), "body": args.get("body", ""),
                     "state": "open", "labels": args.get("labels") or [],
                     "created_at": "today", "indexed": False,
                     "parent": args.get("parent_issue_number")}
            issues.append(issue)
            save(state)
            return {"id": str(issue["id"]), "number": number,
                    "url": f"https://github.com/{args['owner']}/{args['repo']}"
                           f"/issues/{number}"}
        issue = by_number[int(args["issue_number"])]
        for key in ("title", "body", "labels", "state"):
            if key in args:
                issue[key] = args[key]
        save(state)
        return brief(issue)
    if name == "sub_issue_write":
        child = next((i for i in issues if i["id"] == int(args["sub_issue_id"])),
                     None)
        if child is None:
            raise ValueError("sub_issue_id does not match any issue ID "
                             "(the ID is not the issue number)")
        if args["method"] == "add":
            if child.get("parent") and not args.get("replace_parent"):
                raise ValueError("issue already has a parent")
            child["parent"] = int(args["issue_number"])
        elif args["method"] == "remove":
            child["parent"] = None
        save(state)
        return brief(child)
    if name == "add_issue_comment":
        return {"id": 1, "body": args["body"]}
    if name == "list_pull_requests":
        return []
    raise ValueError(f"unknown tool: {name}")


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        msg = json.loads(line)
        method, mid = msg.get("method"), msg.get("id")
        if mid is None:
            continue  # a notification
        if method == "initialize":
            result = {"protocolVersion": msg["params"].get("protocolVersion",
                                                           "2024-11-05"),
                      "capabilities": {"tools": {}},
                      "serverInfo": {"name": "github", "version": "stand-in"}}
        elif method == "tools/list":
            result = {"tools": TOOLS}
        elif method == "tools/call":
            name = msg["params"]["name"]
            args = msg["params"].get("arguments") or {}
            with open(LOG, "a") as log:
                log.write(json.dumps({"tool": name, "args": args}) + "\n")
            try:
                payload = call(name, args)
                result = {"content": [{"type": "text",
                                       "text": json.dumps(payload)}]}
            except Exception as exc:
                result = {"content": [{"type": "text", "text": f"error: {exc}"}],
                          "isError": True}
        elif method == "ping":
            result = {}
        else:
            reply = {"jsonrpc": "2.0", "id": mid,
                     "error": {"code": -32601, "message": "method not found"}}
            sys.stdout.write(json.dumps(reply) + "\n")
            sys.stdout.flush()
            continue
        sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid,
                                     "result": result}) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
