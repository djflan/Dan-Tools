using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Internal;
using Moq;
using NLog;

namespace NLogTesting
{
    internal class Program
    {
        private const string LoggerName = "PatientAccessApiContent";
        private static readonly NLog.Logger Logger = NLog.LogManager.GetLogger(LoggerName);

        private static async Task Main()
        {
            var data = "data";

            var stream = new MemoryStream(Encoding.UTF8.GetBytes(data));

            var httpContext = new DefaultHttpContext
            {
                Request =
                {
                    Body = stream,
                    ContentLength = stream.Length
                }
            };

            await LogAsync(httpContext.Request);
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
