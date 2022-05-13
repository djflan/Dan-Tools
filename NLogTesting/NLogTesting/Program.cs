using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Newtonsoft.Json;
using NLog;

namespace NLogTesting
{
    internal class Program
    {
        private const string LoggerName = "PatientAccessApiContent";
        private static readonly Logger Logger = LogManager.GetLogger(LoggerName);

        private static async Task Main()
        {
            int classIndex = 1;

            var dansTinyClass = new DansTinySerializableClass
            {
                Name = $"{classIndex}",
                Time = DateTime.Now,
                Data = "Some important data."
            };

            DansTinySerializableClass final = null;

            for (var i = 0; i < 2; i++)
            {
                classIndex++;

                final = new DansTinySerializableClass
                {
                    Name = $"{classIndex}",
                    Time = DateTime.Now,
                    Data = JsonConvert.SerializeObject(dansTinyClass)
                };

                dansTinyClass = final;
            }

            await SerializeLogAsync(final);
        }

        private static async Task SerializeLogAsync(DansTinySerializableClass serializabeObject)
        {
            var dansTinyJson = JsonConvert.SerializeObject(serializabeObject);
            var httpContext = CreateContext(dansTinyJson);

            await LogAsync(httpContext.Request);
        }

        private static DefaultHttpContext CreateContext(string jsonEncodedString)
        {
            var stream = new MemoryStream(Encoding.UTF8.GetBytes(jsonEncodedString));

            var httpContext = new DefaultHttpContext
            {
                Request =
                {
                    Body = stream,
                    ContentLength = stream.Length
                }
            };
            return httpContext;
        }

        private static async Task LogAsync(HttpRequest request)
        {
            var readBuffer = new byte[Convert.ToInt32(request.ContentLength.Value)];

            await request.Body.ReadAsync(readBuffer, 0, readBuffer.Length);
            var readBodyText = Encoding.UTF8.GetString(readBuffer);

            Logger.Log(new LogEventInfo(LogLevel.Debug, LoggerName, readBodyText));
        }

        /*
         * request is HttpRequest
         * 
						var buffer = new byte[Convert.ToInt32(request.ContentLength.Value)];
						await request.Body.ReadAsync(buffer, 0, buffer.Length);
						body = Encoding.UTF8.GetString(buffer);
         */
    }
}
