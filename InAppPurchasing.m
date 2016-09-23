//
//  InAppPurchasing.m
//  life
//
//  Created by wujian on 9/22/16.
//  Copyright © 2016 wesk痕. All rights reserved.
//

#import "InAppPurchasing.h"
#import <StoreKit/StoreKit.h>

#if TARGET_IPHONE_SIMULATOR
// 开发时模拟器使用的验证服务器地址
#define ITMS_VERIFY_RECEIPT_URL     @"https://sandbox.itunes.apple.com/verifyReceipt"
#elif TARGET_OS_IPHONE
//真机验证的服务器地址
#define ITMS_VERIFY_RECEIPT_URL        @"https://buy.itunes.apple.com/verifyReceipt"
#endif


@interface InAppPurchasing ()<SKProductsRequestDelegate,SKPaymentTransactionObserver>

@property (nonatomic, strong) SKProductsRequest *request;
@end

@implementation InAppPurchasing

+ (instancetype)sharedInstance
{
    static InAppPurchasing* instance = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [InAppPurchasing new];
    });
    return instance;
}


- (instancetype)init
{
    self = [super init];
    if (self) {
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    }
    return self;
}

- (void)dealloc
{
    [self releaseRequest];
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

- (void)releaseRequest
{
    if (_request) {
        [_request cancel];
        _request.delegate = nil;
        _request = nil;
    }
}
- (void)identifyCanMakePayments:(NSArray *)requestArray
{
    if (requestArray.count == 0) {
        if (self.delegate && [self.delegate respondsToSelector:@selector(updatedTransactions:)]) {
            [self.delegate updatedTransactions:EPaymentTransactionStateAddPaymentFailed];
        }
        return;
    }
    if ([SKPaymentQueue canMakePayments]) {
        [self releaseRequest];
        self.request = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithArray:requestArray]];
        _request.delegate=self;
        [_request start];
    }
    else
    {
        if (self.delegate && [self.delegate respondsToSelector:@selector(updatedTransactions:)]) {
            [self.delegate updatedTransactions:EPaymentTransactionStateNoPaymentPermission];
        }
    }
}

#pragma mark - SKProductsRequestDelegate
- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response
{
    NSLog(@"-----------收到产品反馈信息-------------- 产品ID:%@ 产品数量:%ld",response.invalidProductIdentifiers,response.products.count);
    NSArray *myProducts = response.products;
    
    for(SKProduct *product in myProducts){
        NSLog(@"SKProduct 描述信息%@", [product description]);
        NSLog(@"产品标题 %@" , product.localizedTitle);
        NSLog(@"产品描述信息: %@" , product.localizedDescription);
        NSLog(@"价格: %@" , product.price);
        NSLog(@"Product id: %@" , product.productIdentifier);
    }
    
    if (myProducts && myProducts.count > 0) {
        SKProduct *product = [myProducts objectAtIndex:0];
        if (self.delegate && [self.delegate respondsToSelector:@selector(isProductIdentifierAvailable:)]) {
            if ([self.delegate isProductIdentifierAvailable:product.productIdentifier]) {
                SKPayment *payment = [SKPayment paymentWithProduct:product];
                [[SKPaymentQueue defaultQueue] addPayment:payment];
                return;
            }
        }
    }
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(updatedTransactions:)]) {
        [self.delegate updatedTransactions:EPaymentTransactionStateAddPaymentFailed];
    }
}


#pragma mark - SKPaymentTransactionObserver
- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions
{
    for (SKPaymentTransaction *transaction in transactions)
    {
        EPaymentTransactionState state;
        switch (transaction.transactionState){
            case SKPaymentTransactionStatePurchasing:
            {
                // 连接appStore
                state = EPaymentTransactionStatePurchasing;
            }
                break;
            case SKPaymentTransactionStatePurchased:
            {
                state = EPaymentTransactionStatePurchased;
                //交易完成
                if (isServiceVerify) {
                    [self completeTransaction:transaction];
                }
                else
                {
                    //本地作校验
                    [self verifyPurchase:transaction];
                }
            }
                break;
                
            case SKPaymentTransactionStateFailed:
            {
                //交易失败
                if (transaction.error.code != SKErrorPaymentCancelled)
                {
                    state = EPaymentTransactionStateFailed;
                }else
                {
                    state = EPaymentTransactionStateCancel;
                }

                [self finshTransaction:transaction];
            }
                break;
                
            case SKPaymentTransactionStateRestored:
            {
                state = EPaymentTransactionStateRestored;
                //已经购买过该商品
        
                [self finshTransaction:transaction];
            }
                break;
            case SKPaymentTransactionStateDeferred:
            {
                state = EPaymentTransactionStateDeferred;
            }
                break;
            default:
                break;
        }
        if (self.delegate && [self.delegate respondsToSelector:@selector(updatedTransactions:)]) {
            [self.delegate updatedTransactions:state];
        }

    }
}
// Sent when transactions are removed from the queue (via finishTransaction:).
- (void)paymentQueue:(SKPaymentQueue *)queue removedTransactions:(NSArray<SKPaymentTransaction *> *)transactions
{
    NSLog(@"removedTransactions");
}
// Sent when an error is encountered while adding transactions from the user's purchase history back to the queue.
- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    NSLog(@"restoreCompletedTransactionsFailedWithError");
}

// Sent when all transactions from the user's purchase history have successfully been added back to the queue.
- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
    NSLog(@"paymentQueueRestoreCompletedTransactionsFinished");
}

// Sent when the download state has changed.
- (void)paymentQueue:(SKPaymentQueue *)queue updatedDownloads:(NSArray<SKDownload *> *)downloads
{
    NSLog(@"updatedDownloads");
}

#pragma mark - Private

#pragma mark 验证购买
// 验证购买，在每一次购买完成之后，需要对购买的交易进行验证
// 所谓验证，是将交易的凭证进行"加密"，POST请求传递给苹果的服务器，苹果服务器对"加密"数据进行验证之后，
// 会返回一个json数据，供开发者判断凭据是否有效
// 有些“内购助手”同样会拦截验证凭据，返回一个伪造的验证结果
// 所以在开发时，对凭据的检验要格外小心
- (void)verifyPurchase:(SKPaymentTransaction *)transaction
{
    //ios7开始支持
    NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptURL];
    NSString *encodeStr = [receiptData base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
    NSURL *url = [NSURL URLWithString:ITMS_VERIFY_RECEIPT_URL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10.0f];
    
    NSString *payload = [NSString stringWithFormat:@"{\"receipt-data\" : \"%@\"}", encodeStr];
    NSData *payloadData = [payload dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:payloadData];
    [request setHTTPMethod:@"POST"];

    NSURLResponse *response = nil;
    // 此请求返回的是一个json结果  将数据反序列化为数据字典
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:nil];
    if (data == nil) {
        return;
    }
    NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil];
    if (jsonResponse != nil) {
        if ([[jsonResponse objectForKey:@"status"] intValue] == 0)
        {
            //通常需要校验：bid，product_id，purchase_date，status
            
        }
        else
        {
            //验证失败，检查你的机器是否越狱
        }
    }
    
    //结束交易
    [self finshTransaction:transaction];
}

- (void)completeTransaction:(SKPaymentTransaction *)transaction
{
    //服务器校验
    //TODO ......
    
    bool success;
    if (success) {
        [self finshTransaction:transaction];
        
        //refresh view
        if (self.delegate && [self.delegate respondsToSelector:@selector(buySuccess:)]) {
            [self.delegate buySuccess:transaction];
        }

    }
    else
    {
        
        //服务器返回明确非法交易码 结束交易 否者继续请求服务器 或暂停 不能结束交易
        bool hasExpressError;
        if (hasExpressError) {
            [self finshTransaction:transaction];
            
            if (self.delegate && [self.delegate respondsToSelector:@selector(buyFailed:)]) {
                [self.delegate buyFailed:nil];
            }
        }
        else
        {
            //重试多次 
        }

    }
}



- (void)finshTransaction:(SKPaymentTransaction *)transaction
{
    //结束交易
    [[SKPaymentQueue defaultQueue] finishTransaction: transaction];
}


@end
