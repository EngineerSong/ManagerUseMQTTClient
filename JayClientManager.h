//
//  JayClientManager.h
//  MQTTTest
//
//  Created by barara on 16/3/24.
//  Copyright © 2016年 Jay. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "FoodGlobal.h"
#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "MyBar.h"
#import "AFNetworkTool.h"
#import "RootViewController.h"
#import "PersonViewController.h"
#import <MQTTClient/MQTTClient.h>
#import <MQTTClient/MQTTSessionManager.h>
#import "JKAssets.h"

typedef void(^OneBlock)(NSString* oneChatString);
typedef void(^GroupBlock)(NSString* groupChatString);
typedef void(^MessageBlock)(NSString* MessageString);

@interface JayClientManager : NSObject <MQTTSessionManagerDelegate>

@property (nonatomic, copy) OneBlock oneBlock;
@property (nonatomic, copy) GroupBlock groupBlock;
@property (nonatomic, copy) MessageBlock messageBlock;



@property (strong, nonatomic) MQTTSessionManager *manager;




//创建串行队列,用于收发消息页中数据源的操作
@property (nonatomic, strong) dispatch_queue_t dataQueue;
//创建串行队列,用于数据库操作
@property (nonatomic, strong) dispatch_queue_t queue;
//第一个参数为串行队列的名称，是c语言的字符串
//第二个参数为队列的属性，一般来说串行队列不需要赋值任何属性，所以通常传空值（NULL）
@property (nonatomic, strong) dispatch_queue_t sendDataQueue;
//创建串行队列，用于获取单聊历史记录
@property (nonatomic, strong) dispatch_queue_t getSingleHistoryPageQueue;
//发表动态串行队列
@property (nonatomic, strong) dispatch_queue_t publishDynamicQueue;
//返回数据库历史记录
//@property (nonatomic, strong) NSMutableArray *historyMuArr;


//数据库
@property (nonatomic, strong) FMDatabase *db;


//判断消息表中是否已经存在收到的该条消息
@property (nonatomic, assign) BOOL isExistMessage;

//指针指向单聊中对方的用户ID
@property (nonatomic, copy) NSString *userIdFromPersonChat;
//指针指向群聊中的群ID
@property (nonatomic, copy) NSString *groupIdFromGroupChat;

//指针指向用户参与的游戏ID
@property (nonatomic, copy) NSString *gameIdFromGroupChat;


//存储扫码得到的店铺ID和桌号等信息
@property (nonatomic, copy) NSString *scanStr;

//指针指向RootViewController中的mybar
@property (nonatomic, strong) MyBar *mybar;

//获取屏幕当前展示的页面
- (UIViewController *)getCurrentVC;
//获取模态出来的页面
- (UIViewController *)getPresentedViewController;

//退出登陆，以未登陆状态刷新所有页面
- (void)exitLogin;


//登录成功调用，更改数据库
- (void)loginSuccessToChangeDb;
//退出登录调用，更改数据库
- (void)exitLoginToChangeDb;

+ (instancetype)sharedClient;
- (void)mgrReceiveMessageWith:(NSMutableDictionary *)dict;


//传入要发送的字典和shopStr,返回主题topStr
- (NSString *)getTopStrFromSendDictionary:(NSMutableDictionary *)sendDictionary andShopStr:(NSString *)shopStr;

//删除群聊记录，传入群ID
- (void)removeGroupHistoryWithGroupName:(NSString *)groupName;
//删除单聊记录，传入对方用户ID
- (void)removePersonHistoryWithPersonName:(NSString *)personName;
//删除一条消息记录，传入对方用户ID
- (void)removeRecordFromMessageListWithUserID:(NSString *)userID;


//    dispatch_async([JayClientManager sharedClient].queue, ^{
//
//        //在这里调用历史记录或者分页加载记录的方法，获得数据
//
//        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//
//            //处理获得的数据
//
//            dispatch_async(dispatch_get_main_queue(), ^(){
//                //这里是主线程，在此处更新界面
//            });
//        });
//    });

/**
 *  进群获取历史记录
 *
 *  @param groupName 群组ID
 *  @param handle    成功回调
 */
-(void)getHistoryOfGroupWithGroupName:(NSString *)groupName success:(void(^)(NSArray * history))handle;
/**
 *  进入获取历史记录
 *
 *  @param groupName 对方
 *  @param handle    成功回调
 */
-(void)getHistoryOfPersonWithSenderName:(NSString *)senderName success:(void(^)(NSArray * history))handle;
//获取消息列表
-(void)getMessageList:(void(^)(NSArray * messageList))handle;
//获取动态列表
- (void)getDynamicList:(void(^)(NSArray * dynamicList))handle;


/*****************************   聊天记录分页加载   ******************************/
//根据传入的uid获取num条群聊记录，本方法提供uid向上num条数据
/**
 *  获取群聊历史记录
 *  根据传入的uid获取num条群聊记录，本方法提供uid向上num条数据
 *  @param groupName 群组ID
 *  @param uidString uid
 *  @param num       获取的历史记录条数
 *  @param handle    获取的历史记录数组回调
 */
- (void)getUpPageHistoryOfGroupWithGroupName:(NSString *)groupName andUID:(NSString *)uidString andNumbers:(int)num success:(void(^)(NSArray * History))handle;
//根据传入的uid获取num条群聊记录，本方法提供uid向下num条数据
- (void)getDownPageHistoryOfGroupWithGroupName:(NSString *)groupName andUID:(NSString *)uidString andNumbers:(int)num success:(void(^)(NSArray * history))handle;

/**
 *  下拉获取历史记录
 *  根据传入的uid获取num条单聊记录，本方法提供uid向上num条数据
 *  @param userID    接受者ID
 *  @param uidString uid
 *  @param num       获取的历史记录条数
 *  @param handle    获取的历史记录数组回调
 */
- (void)getUpPageHistoryOfPersonWithUserID:(NSString *)userID andUID:(NSString *)uidString andNumbers:(int)num success:(void(^)(NSArray * History))handle;
//根据传入的uid获取num条单聊记录，本方法提供uid向下num条数据
- (void)getDownPageHistoryOfPersonWithUserID:(NSString *)userID andUID:(NSString *)uidString andNumbers:(int)num success:(void(^)(NSArray * history))handle;

//在线程中调用该方法
//dispatch_async([JayClientManager sharedClient].queue, ^{
//});
//单人消息发送时调用,将消息存入数据库,返回uid
- (void)messageToPersonSuccessWithSendDictionary:(NSMutableDictionary *)sendDictionary andMessageStatus:(NSString *)messageStatus success:(void(^)(int returnInt))handle;
//修改单聊消息中的messageStatus，传入对方用户ID，消息的uid和新的messageStatus
- (void)writeNewMsgInPersonWithPersonID:(NSString *)personId andUID:(NSString *)uidString andMessageStatus:(NSString *)messageStatus success:(void(^)(BOOL resChange))handle;
//修改单聊消息中的msg，传入对方用户ID，消息的uid和新的msg
- (void)writeNewMsgInPersonWithPersonID:(NSString *)personId andUID:(NSString *)uidString andMsg:(NSString *)msg success:(void(^)(BOOL resChange))handle;
//群聊消息发送时调用,将消息存入数据库,返回uid
- (void)messageToGroupSuccessWithSendDictionary:(NSMutableDictionary *)sendDictionary andMessageStatus:(NSString *)messageStatus success:(void(^)(int returnInt))handle;
//修改群聊消息中的msg，传入对方用户ID，消息的uid和新的messageStatus
- (void)writeNewMsgInGroupWithGroupID:(NSString *)GroupId andUID:(NSString *)uidString andMessageStatus:(NSString *)messageStatus success:(void(^)(BOOL resChange))handle;
//修改群聊消息中的msg，传入对方用户ID，消息的uid和新的msg
- (void)writeNewMsgInGroupWithGroupID:(NSString *)GroupId andUID:(NSString *)uidString andMsg:(NSString *)msg success:(void(^)(BOOL resChange))handle;



//点击群组中未读的阅后即焚和语音消息时调用，传入字符串格式的群ID和cell对应的uid，将数据库中对应数据的isRead变为@"1"
- (void)fireAfterReadInGroupWith:(NSString *)groupId andUID:(NSString *)uidString;
//点击单聊中未读的阅后即焚和语音消息时调用，传入字符串格式的用户ID和cell对应的uid，将数据库中对应数据的isRead变为@"1",点击自己发的消息时不调用
- (void)fireAfterReadInPersonWith:(NSString *)personId andUID:(NSString *)uidString;

//同意加为好友，点击单聊中未读的好友请求消息时调用
- (void)acceptMakeFriendsWithPersonId:(NSString *)personId andUID:(NSString *)uidString;
//拒绝加为好友，点击单聊中未读的好友请求消息时调用
- (void)refuseMakeFriendsWithPersonId:(NSString *)personId andUID:(NSString *)uidString;
//上传动态缓存图片返回url数组
-(void)publishDynamicAfterGetUrl:(JKAssets *)asset success:(void(^)(NSString * urlString))handle;
@end
