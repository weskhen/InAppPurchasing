//
//  InAppPurchasing.h
//  life
//
//  Created by wujian on 9/22/16.
//  Copyright © 2016 wesk痕. All rights reserved.
//

#import <Foundation/Foundation.h>

#define isServiceVerify  1 //支付完成返回 校验方式


typedef enum : NSUInteger {
    EPaymentTransactionStateNoPaymentPermission, //没有Payment权限
    EPaymentTransactionStateAddPaymentFailed, //addPayment失败
    EPaymentTransactionStatePurchasing,//正在购买
    EPaymentTransactionStatePurchased,//购买完成(销毁交易)
    EPaymentTransactionStateFailed, //购买失败(销毁交易)
    EPaymentTransactionStateCancel,//用户取消
    EPaymentTransactionStateRestored,//恢复购买(销毁交易)
    EPaymentTransactionStateDeferred, //最终状态未确定
} EPaymentTransactionState;


#define _InAppPurchasing [EInAppPurchasing sharedInstance]

@class SKProduct;
@class SKPaymentTransaction;
@protocol EInAppPurchasingDelegate <NSObject>

@required
//本地确认物品是否可用 一般返回true
- (BOOL)isProductIdentifierAvailable:(NSString *)productIdentifier;


@optional

- (void)updatedTransactions:(EPaymentTransactionState)state;

//购买成功
- (void)buySuccess:(SKPaymentTransaction*)transaction;

//购买失败
- (void)buyFailed:(NSError *)errorInfo;
@end

@interface InAppPurchasing : NSObject

+ (instancetype)sharedInstance;

@property (nonatomic, weak) id<EInAppPurchasingDelegate> delegate;

//[[NSArray alloc] initWithObjects:@"com.wesk.product1",nil];
- (void)identifyCanMakePayments:(NSArray *)requestArray;

@end
