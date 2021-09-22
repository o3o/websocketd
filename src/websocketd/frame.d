module websocketd.frame;
import websocketd.checkpoint;

enum Op : ubyte {
   CONT = 0,
   TEXT = 1,
   BINARY = 2,
   CLOSE = 8,
   PING = 9,
   PONG = 10
}

struct Frame {
   bool fin;
   Op op;
   bool masked;
   ulong length;
   ubyte[4] mask;
   bool done = false;
   ubyte[] data;

   ulong remaining() @property {
      return this.length - this.data.length;
   }

   ubyte[] serialize() {
      ubyte[] result = [];

      result ~= cast(ubyte)(fin ? 1 << 7 : 0) ^ cast(ubyte)op;

      ubyte b2 = masked ? 1 << 7 : 0;
      if (length < 126) {
         result ~= b2 ^ cast(ubyte)length;
      } else if ((length >> 16) == 0) {
         result ~= b2 ^ 126;
         ubyte[2] lens;
         lens[1] = cast(ubyte)length & 0b11111111;
         lens[0] = cast(ubyte)(length >> 8) & 0b11111111;
         result ~= lens;
      } else {
         result ~= b2 ^ 127;
         ubyte[8] lens;
         for (size_t i = 0; i < 8; i++)
            lens[7 - i] = cast(ubyte)(length >> (i * 8)) & 0b11111111;
         result ~= lens;
      }

      if (masked)
         result ~= mask;

      if (masked)
         for (size_t i = 0; i < data.length; i++)
            result ~= data[i] ^ mask[i % 4];
      else
         result ~= data;

      return result;
   }
}

auto next(size_t n = 1)(ref ubyte[] data, size_t m = n) {
   assert(data.length >= m);
   static if (n == 1) {
      ubyte b = data[0];
      data = data[1 .. $];
      return b;
   } else {
      ubyte[] bs = data[0 .. m];
      data = data[m .. $];
      return bs;
   }
}

Frame parse(string source, ubyte[] data) {
   // `Frame` is what we're building
   // "data" is the name of the variable that contains the data to consume
   // "frame" is the name of the variable we're building
   // "source" is the name of a "session identifier"
   mixin(CheckpointSetup!Frame("data", "frame", "source", // fin_rsv_opcode is the name of the first checkpoint
         // `data.length >= 1` is the condition to enter this state
         // (otherwise what's after the mixin gets executed)
         "fin_rsv_opcode".Checkpoint(q{ data.length >= 1 }, q{
            frame = Frame.init;
            ubyte b = data.next; // next() modifies `data` by consuming the first byte
            frame.fin = cast(bool) (b >>> 7);
            assert(((b >>> 4) & 0b111) == 0);
            frame.op = cast(Op) (b & 0b1111);
        }), "mask_len".Checkpoint(q{ data.length >= 1 }, q{
            ubyte b = data.next;
            frame.masked = cast(bool) (b >>> 7);
            frame.length = cast(ulong) (b & 0b1111111);
            if (frame.length <= 125) mixin (changeState("maskOn_mask"));
            if (frame.length == 127) mixin (changeState("len127_ext_len"));
        }), "len126_ext_len".Checkpoint(q{ data.length >= 2 }, q{
            frame.length = cast(ulong) data.next;
            frame.length <<= 8;
            frame.length += cast(ulong) data.next;
            mixin (changeState("maskOn_mask")); // edge case: length=127
        }), "len127_ext_len".Checkpoint(q{ data.length >= 8 }, q{
            frame.length = cast(ulong) data.next;
            for (int i=0; i<7; i++) {
                frame.length <<= 8;
                frame.length += cast(ulong) data.next;
            }
        }), "maskOn_mask".Checkpoint(q{ data.length >= (frame.masked ? 4 : 0) }, q{
            if (frame.masked) {
                frame.mask = data.next!4; // next!n when n > 1 returns ubyte[]
            }
        }), // we don't want to wait for all the data to arrive at once (if we wanted then the condition
         // should be `data.length >= frame.length`), we prefer processing as it comes
         "message_extraction".Checkpoint(q{ (frame.length > 0 && data.length >= 1) || (frame.length == 0) }, q{
            if (frame.masked) {
                size_t i = frame.data.length;
                while (frame.remaining > 0 && data.length > 0) {
                    ubyte b = data.next;
                    frame.data ~= b ^ frame.mask[i % 4];
                    i++;
                }
            } else if (data.length >= frame.remaining)
                frame.data ~= data.next!2(frame.remaining);
            else frame.data ~= data.next!2(data.length);
        }), "done".Checkpoint(q{ true }, q{
            // to allow for streaming we have this changeState(..) loop
            if (frame.remaining > 0)
                mixin (changeState("message_extraction"));
            frame.done = true;
        })));

   return frame;
}

unittest { // test multiple frames in one go
   auto f1 = Frame(true, Op.TEXT, true, 6, [0, 0, 0, 0], true, [0, 1, 2, 3, 4, 5]);
   auto f2 = Frame(false, Op.BINARY, true, 3, [0, 1, 2, 3], true, [8, 7, 6]);
   auto f3 = Frame(false, Op.CLOSE, true, 10, [0, 1, 2, 3], true, [9, 8, 7, 6, 5, 4, 3, 2, 1, 0]);
   auto d = f1.serialize ~ f2.serialize ~ f3.serialize;
   auto f4 = "u0".parse(d);
   auto f5 = "u0".parse([]);
   auto f6 = "u0".parse([]);
   assert(f1 == f4);
   assert(f2 == f5);
   assert(f3 == f6);
}

unittest { // test streaming one byte at a time
   auto f = Frame(true, Op.TEXT, true, 6, [1, 2, 3, 4], true, [0, 1, 2, 3, 4, 5]);
   ubyte[] data = f.serialize;
   foreach (b; data[0 .. $ - 1]) {
      auto _f = "u1".parse([b]);
      assert(!_f.done);
   }
   auto _f = "u1".parse([data[$ - 1]]);
   assert(_f.done);
   assert(f == _f);
}

unittest { // test some funky streaming
   ubyte[] data;
   for (size_t i = 0; i < 1024 * 1024; i++)
      data ~= cast(ubyte)i;
   auto f = Frame(false, Op.BINARY, true, data.length, [0, 0, 0, 0], true, data);
   ubyte[] serialized = f.serialize;
   size_t i0 = 0, i1 = 0, t = 1;
   do {
      i0 = i1;
      i1 = i0 + (((i0 & i1 | 0b11) ^ t) & 0b111111);
      if (i1 >= serialized.length)
         i1 = serialized.length;
      t++;
      auto _f = "u2".parse(serialized[i0 .. i1]);
      if (i1 == serialized.length) {
         assert(_f.done);
         assert(_f == f);
      } else
         assert(!_f.done);
   }
   while (i1 < serialized.length);
}

unittest { // test edge-case length=127
   ubyte[] data;
   for (size_t i = 0; i < 127; i++)
      data ~= cast(ubyte)i;
   auto f = Frame(true, Op.BINARY, false, data.length, [0, 0, 0, 0], true, data);
   auto _f = "u3".parse(f.serialize);
   assert(f == _f);
}

unittest { // test edge-case length=0
   import std.stdio;

   auto f = Frame(true, Op.CLOSE, false, 0, [0, 0, 0, 0], true, []);
   auto _f = "u4".parse(f.serialize);
   assert(f == _f);
}
