USE [LASS]
GO

DROP PROCEDURE [dbo].[LASS_SalesTaxBatch_Populate]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[LASS_SalesTaxBatch_Populate]
(
	 @InvoiceGenerationSessionId		UNIQUEIDENTIFIER = NULL	
	,@UserName		NVARCHAR(128)
	,@ReturnCode	INT				OUTPUT
    ,@ReturnMsg		NVARCHAR(256)	OUTPUT
)
/*=========================================================
NAME:             [dbo].[LASS_SalesTaxBatch_Populate]
DESCRIPTION:      Creates Sales Tax Batches for all platforms -- this is the entry point from LASS.
					Delegate the population to each specific platform stored procedure.
				  
MODIFICATIONS:
  AUTHOR        date        DESC
  mgolden       20190312    Initial Version - APX-3096 - Connect to Avalara to request sales tax data, then hibernate
  dflanigan     20240310    Added support for generating lis / lads billing transaction data.
=========================================================
--DEBUG
DECLARE @ReturnCode	int
DECLARE @ReturnMsg	nvarchar(256)
DECLARE @InvoiceId UNIQUEIDENTIFIER = ''

EXEC [dbo].[LASS_SalesTaxBatch_Maestro_Populate] @InvoiceId, @UserName, @ReturnCode output, @ReturnMsg output
SELECT @ReturnCode AS ReturnCode, @ReturnMsg AS ReturnMsg
=========================================================
*/

AS

BEGIN

	SET NOCOUNT ON

    -- Generate Billing Trasaction data for LIS and LADS
    EXEC LASS.dbo.LASS_GenerateBillingTransactionData_LIS_LADS @InvoiceGenerationSessionId

    -- Creates sales tax batches for all platforms (LIS, LADS, and Maestro - was initially written for Maestro)
	EXEC LASS.dbo.LASS_SalesTaxBatch_Maestro_Populate @InvoiceGenerationSessionId, @UserName, @ReturnCode output, @ReturnMsg output

END

GO
