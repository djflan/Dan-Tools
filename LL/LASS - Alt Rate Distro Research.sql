USE LASS
GO

DECLARE @InvoiceGenerationSessionKey BIGINT = 138130
DECLARE @TransactionUserAddedPrefix VARCHAR(128) = (SELECT CONCAT('lass-ll-btdp-gen','|',CAST(@InvoiceGenerationSessionKey AS VARCHAR),'|'))

DECLARE @InvoiceGenerationSessionId UNIQUEIDENTIFIER = (SELECT InvoiceGenerationSessionId FROM LASS.dbo.LASS_InvoiceGenerationSessions WHERE InvoiceGenerationSessionKey = @InvoiceGenerationSessionKey)
DECLARE @SalesTaxBatchStatusKeyNew INT = (SELECT SalesTaxBatchStatusKey FROM LASS.dbo.LASS_SalesTaxBatchStatuses WHERE SalesTaxBatchStatusId = '7BB2234C-2EEC-4AC3-BBA0-E4F9EF019E9C')

-- INSERT INTO LASS.dbo.LASS_SalesTaxBatch 
-- 		(
-- 			SalesTaxBatchId,
-- 			InvoiceLineItemKey, 			
-- 			SalesTaxBatchStatusKey,
-- 			InvoiceLineItemGroupKey,
-- 			LineItemKey,
-- 			TaxCode,
-- 			TaxCategory,
-- 			UserAdded,
-- 			DateAdded,
-- 			IsActive		
-- 		)
		SELECT 
			NEWID(),
			ili.InvoiceLineItemKey,
			@SalesTaxBatchStatusKeyNew,
			ili.InvoiceLineItemGroupKey,
			ili.LineItemKey,
			stc.TaxCode,
			li.SalesTaxItemCategory,
			'dflanigan - lass-ll-btdp-gen',
			GETDATE(),
			1
		FROM LASS.dbo.LASS_invoices i
			INNER JOIN LASS.dbo.LASS_InvoiceGenerationSessions igs ON igs.InvoiceGenerationSessionKey = i.InvoiceGenerationSessionKey
			INNER JOIN LASS.dbo.LASS_InvoiceLineItems ili ON ili.InvoiceKey = i.InvoiceKey
			INNER JOIN LASS.dbo.LASS_LineItems li ON li.LineItemKey = ili.LineItemKey
			INNER JOIN LASS.dbo.LASS_SalesTaxCodes stc ON stc.SalesTaxCodeKey = li.SalesTaxCodeKey
			INNER JOIN LASS.dbo.LASS_InvoiceLineItemBillingActivities iliba ON iliba.InvoiceLineItemKey = ili.InvoiceLineItemKey AND iliba.IncludeInSalesTaxBatch = 1			
		-- Only create a batch for line items that have delivery point records.
		WHERE igs.InvoiceGenerationSessionId = @InvoiceGenerationSessionId
			AND (
				-- Creates stb items for Maestro (when btdp exist)
                EXISTS(
                    SELECT * 
						FROM LASS.dbo.LASS_BillingActivityBatchCategoryDetails babcd
                        -- *** CONSIDER FINDING ANOTHER WAY TO DO THIS BABCD CAN BE ASSOCIATED TO MUTIPLE LINE ITEMS
							 INNER JOIN LASS.dbo.tblBillingTransactionDeliveryPoints btdp ON btdp.BillingTransactionGuid = babcd.BillingTransactionGuid AND btdp.IsActive = 1
						WHERE babcd.BillingActivityBatchCategoryKey = iliba.BillingActivityBatchCategoryKey
					)
				 -- Create a batch if the line item should use the customer tax address
				 -- There won't be any delivery points associated to the category details with this setting (Services)
			   OR li.UseCustomerTaxAddress = 1)
		GROUP BY ili.InvoiceLineItemKey,			
				 ili.InvoiceLineItemGroupKey,
				 ili.LineItemKey,
				 stc.TaxCode,
				 li.SalesTaxItemCategory;

RETURN

SELECT 
    stb.SalesTaxBatchKey,
    btdp.City,
    btdp.StateRegion,
    btdp.PostalCode,
    SUM(btdp.Quantity) AS Quantity,
    ROW_NUMBER() OVER (PARTITION BY ili.ExtendedAmount, stb.SalesTaxBatchKey ORDER BY btdp.PostalCode) AS LineNumber,
    COUNT(*) OVER (PARTITION BY ili.ExtendedAmount, stb.SalesTaxBatchKey) AS LinesPerBatch,
    ROUND(CONVERT(NUMERIC(25, 10), ili.ExtendedAmount) / SUM(SUM(btdp.Quantity)) OVER (PARTITION BY ili.ExtendedAmount, stb.SalesTaxBatchKey), 8) AS ProRataRate,
    CONVERT(NUMERIC(25, 3), ili.ExtendedAmount) AS LineItemPrice,
    ISNULL(clirm.Price, 0) AS UnitPrice,
    clir.RateTypeKey,
    btdp.DestinationCode,
    li.IsSalesTaxExportable
FROM LASS_Invoices (NOLOCK) i
    INNER JOIN LASS_InvoiceGenerationSessions (NOLOCK) igs ON igs.InvoiceGenerationSessionKey = i.InvoiceGenerationSessionKey  
    INNER JOIN LASS_InvoiceLineItems (NOLOCK) ili ON ili.InvoiceKey = i.InvoiceKey
    INNER JOIN LASS_SalesTaxBatch (NOLOCK) stb ON stb.InvoiceLineItemKey = ili.InvoiceLineItemKey
    INNER JOIN LASS_LineItems (NOLOCK) li ON li.LineItemKey = ili.LineItemKey
    INNER JOIN LASS_SalesTaxCodes (NOLOCK) stc ON stc.SalesTaxCodeKey = li.SalesTaxCodeKey
    INNER JOIN LASS_InvoiceLineItemBillingActivities (NOLOCK) iliba ON iliba.InvoiceLineItemKey = ili.InvoiceLineItemKey AND iliba.IncludeInSalesTaxBatch = 1
    INNER JOIN LASS_ClientLineItemRateModels (NOLOCK) clirm ON clirm.ClientLineItemRateModelKey = iliba.ClientLineItemRateModelKey
    INNER JOIN LASS_ClientLineItemRates (NOLOCK) clir ON clir.ClientLineItemRateKey = iliba.ClientLineItemRateKey
    INNER JOIN LASS_BillingActivityBatchCategoryDetails (NOLOCK) AS babcd ON iliba.BillingActivityBatchCategoryKey = babcd.BillingActivityBatchCategoryKey
    INNER JOIN LASS.dbo.tblBillingTransactions (NOLOCK) bt ON bt.UserAdded LIKE (CONCAT(@TransactionUserAddedPrefix, CAST(ili.InvoiceLineItemKey AS VARCHAR), '|%'))
    INNER JOIN LASS.dbo.tblBillingTransactionDeliveryPoints btdp (NOLOCK) ON btdp.BillingTransactionGuid = bt.BillingTransactionGuid AND btdp.IsActive = 1
WHERE 
    igs.InvoiceGenerationSessionKey = @InvoiceGenerationSessionKey
    AND li.UseCustomerTaxAddress = 0
GROUP BY stb.SalesTaxBatchKey,
						btdp.City,
						btdp.StateRegion,
						btdp.PostalCode,				 
						clir.RateTypeKey,
						ili.ExtendedAmount,
						clirm.Price,
						clir.RateTypeKey,
						btdp.DestinationCode,
						li.IsSalesTaxExportable
--group by ili.InvoiceLineItemKey, babcd.BillingTransactionGuid
--ORDER by ili.InvoiceLineItemKey
/*
SELECT		
				 stb.SalesTaxBatchKey
				,btdp.City
				,btdp.StateRegion
				,btdp.PostalCode
				-- ,CASE
                --     WHEN MIN(btdp.UserAdded) LIKE 'lass-ll-btdp-gen%' -- LIS/LADS Generated BTDP
                --         THEN
                --             MIN(btdp.Quantity) -- Will already be grouped
                --         ELSE
                --             SUM(btdp.Quantity)
                --     END AS Quantity
                ,SUM(btdp.Quantity) AS Quantity
				,ROW_NUMBER() OVER (PARTITION BY ili.ExtendedAmount, stb.SalesTaxBatchKey ORDER BY btdp.PostalCode) AS LineNumber
				,COUNT(*) OVER (PARTITION BY ili.ExtendedAmount, stb.SalesTaxBatchKey) AS LinesPerBatch
				-- ,CASE 
                --     WHEN MIN(btdp.UserAdded) LIKE 'lass-ll-btdp-gen%' -- LIS/LADS Generated BTDP
                --         THEN
                --             ROUND(CONVERT(NUMERIC(25, 10), ili.ExtendedAmount) / SUM(MIN(btdp.Quantity)) OVER (PARTITION BY ili.ExtendedAmount, stb.SalesTaxBatchKey), 8)
                --         ELSE
                --             ROUND(CONVERT(NUMERIC(25, 10), ili.ExtendedAmount) / SUM(SUM(btdp.Quantity)) OVER (PARTITION BY ili.ExtendedAmount, stb.SalesTaxBatchKey), 8) 
                --     END AS ProRataRate
                ,ROUND(CONVERT(NUMERIC(25, 10), ili.ExtendedAmount) / SUM(SUM(btdp.Quantity)) OVER (PARTITION BY ili.ExtendedAmount, stb.SalesTaxBatchKey), 8) AS ProRataRate
				,CONVERT(NUMERIC(25, 3), ili.ExtendedAmount) AS LineItemPrice
				,ISNULL(clirm.Price, 0) AS UnitPrice		
				,clir.RateTypeKey
				,btdp.DestinationCode		
				,li.IsSalesTaxExportable	
			FROM LASS.dbo.LASS_invoices i
				INNER JOIN LASS.dbo.LASS_InvoiceGenerationSessions igs ON igs.InvoiceGenerationSessionKey = i.InvoiceGenerationSessionKey
				INNER JOIN LASS.dbo.LASS_InvoiceLineItems ili ON ili.InvoiceKey = i.InvoiceKey
				INNER JOIN LASS.dbo.LASS_SalesTaxBatch stb ON stb.InvoiceLineItemKey = ili.InvoiceLineItemKey			
				INNER JOIN LASS.dbo.LASS_LineItems li ON li.LineItemKey = ili.LineItemKey
				INNER JOIN LASS.dbo.LASS_SalesTaxCodes stc ON stc.SalesTaxCodeKey = li.SalesTaxCodeKey
				INNER JOIN LASS.dbo.LASS_InvoiceLineItemBillingActivities iliba ON iliba.InvoiceLineItemKey = ili.InvoiceLineItemKey AND iliba.IncludeInSalesTaxBatch = 1	
				INNER JOIN LASS.dbo.LASS_ClientLineItemRateModels clirm ON clirm.ClientLineItemRateModelKey = iliba.ClientLineItemRateModelKey		
				INNER JOIN LASS.dbo.LASS_ClientLineItemRates clir ON clir.ClientLineItemRateKey = iliba.ClientLineItemRateKey
				INNER JOIN LASS.dbo.LASS_BillingActivityBatchCategoryDetails AS babcd ON iliba.BillingActivityBatchCategoryKey = babcd.BillingActivityBatchCategoryKey
				INNER JOIN LASS.dbo.tblBillingTransactionDeliveryPoints btdp 
                            --WITH (INDEX = [IX_tblBillingTransactionDeliveryPoints_BillingTransactionGuid]) -- Change suggested by: David McCarthy
                            ON btdp.BillingTransactionGuid = babcd.BillingTransactionGuid AND btdp.IsActive = 1
			WHERE li.UseCustomerTaxAddress = 0
			  AND igs.InvoiceGenerationSessionId = @InvoiceGenerationSessionId
			GROUP BY stb.SalesTaxBatchKey,
						btdp.City,
						btdp.StateRegion,
						btdp.PostalCode,				 
						clir.RateTypeKey,
						ili.ExtendedAmount,
						clirm.Price,
						clir.RateTypeKey,
						btdp.DestinationCode,
						li.IsSalesTaxExportable
		)
*/