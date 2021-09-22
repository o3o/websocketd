module websocketd.request;

import std.conv : to;
import std.ascii : isWhite;
import std.algorithm : endsWith;

struct Request {
   string method;
   string path;
   string httpVersion;
   string[string] headers;
   string message;
   bool done = false;

   static Request parse(ubyte[] bytes) {
      static ubyte[] data = [];
      static Request req = Request();

      data ~= bytes;
      string message = (cast(char[])data).to!string;
      if (!message.endsWith("\r\n\r\n"))
         return req;

      size_t i = 0;
      string token = "";

      // get method
      for (; i < message.length; i++) {
         if (message[i] == ' ')
            break;
         token ~= message[i];
      }
      i++; // skip whitespace
      req.method = token;
      token = "";

      // get path
      for (; i < message.length; i++) {
         if (message[i] == ' ')
            break;
         token ~= message[i];
      }
      i++;
      req.path = token;
      token = "";

      // get version
      for (; i < message.length; i++) {
         if (message[i] == '\r')
            break;
         token ~= message[i];
      }
      i++; // skip \r
      if (message[i] != '\n')
         return req;
      i++;
      req.httpVersion = token;
      token = "";

      // get headers
      string key = "";
      for (; i < message.length; i++) {
         token = "";
         key = "";
         if (message[i] == '\r')
            break;
         for (; i < message.length; i++) {
            if (message[i] == ':' || message[i].isWhite)
               break;
            token ~= message[i];
         }
         i++;
         key = token;
         token = "";
         for (; i < message.length; i++)
            if (!message[i].isWhite)
               break; // ignore whitespace
         for (; i < message.length; i++) {
            if (message[i] == '\r')
               break;
            token ~= message[i];
         }
         i++;
         if (message[i] != '\n')
            return req;
         req.headers[key] = token;
      }

      i++;
      if (message[i] != '\n')
         return req;
      i++;

      req.message = message[i .. $];
      req.done = true;
      Request ans = req;
      req = Request.init;
      data = [];
      return ans;
   }
}
